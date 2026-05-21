import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_album.repository.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:openapi/api.dart';

enum SortAction { delete, reviewLater, sorted }

class UndoRecord {
  const UndoRecord({
    required this.asset,
    required this.action,
    required this.quickPickIds,
    this.previousQuickPickIds = const [],
    this.starRating = 0,
    this.previousStarRating = 0,
    this.wasInNew = false,
  });

  final AssetResponseDto asset;
  final SortAction action;

  /// Quick-pick (user) albums the asset was sorted INTO.
  final List<String> quickPickIds;

  /// Quick-pick (user) albums the asset was in BEFORE the sort (edit mode).
  final List<String> previousQuickPickIds;

  /// Star rating applied by this sort (0 = none, 1–3).
  final int starRating;

  /// Star rating the asset had before this sort (edit mode).
  final int previousStarRating;

  /// Whether the asset was in the _New album before sorting (so undo knows
  /// whether to put it back there).
  final bool wasInNew;
}

/// Executes the three sort-deck actions against the Immich API.
///
/// Album add/remove are mirrored into the local Drift DB so the Albums view
/// reflects changes without a full re-sync.
class SortActionService {
  const SortActionService(
    this._assetRepo,
    this._albumRepo,
    this._albumsApi,
    this._driftAlbumRepo,
  );

  final AssetApiRepository _assetRepo;
  final AlbumApiRepository _albumRepo;
  final AlbumsApi _albumsApi;
  final DriftRemoteAlbumRepository _driftAlbumRepo;

  String? _kindId(List<AlbumResponseDto>? albums, String kind) =>
      albums?.where((a) => a.systemKind == kind).map((a) => a.id).firstOrNull;

  /// Adds an asset to an album on the server, then mirrors the change into the
  /// local Drift DB so the Albums view reflects it without a full re-sync.
  /// The local mirror is best-effort: a failure (e.g. album/asset not yet in
  /// the local cache) must never fail the authoritative server operation.
  Future<void> _albumAdd(String albumId, String assetId) async {
    await _albumRepo.addAssets(albumId, [assetId]);
    try {
      await _driftAlbumRepo.addAssets(albumId, [assetId]);
    } catch (_) {
      // Local cache will catch up on the next remote sync.
    }
  }

  Future<void> _albumRemove(String albumId, String assetId) async {
    await _albumRepo.removeAssets(albumId, [assetId]);
    try {
      await _driftAlbumRepo.removeAssets(albumId, [assetId]);
    } catch (_) {
      // Local cache will catch up on the next remote sync.
    }
  }

  /// Reconciles the asset's star-album membership to exactly [rating]:
  /// it ends up in only the matching star album (or none for 0), and its
  /// favorite flag tracks whether it has any stars. Star albums are exclusive
  /// — a 3★ photo lives in ⭐⭐⭐ only, not also in ⭐ and ⭐⭐.
  Future<void> _applyStarRating(
    List<AlbumResponseDto>? albums,
    String assetId,
    int rating,
  ) async {
    final byRating = <int, String?>{
      1: _kindId(albums, 'one_star'),
      2: _kindId(albums, 'two_star'),
      3: _kindId(albums, 'three_star'),
    };
    for (final entry in byRating.entries) {
      final albumId = entry.value;
      if (albumId == null) continue;
      if (entry.key == rating) {
        await _albumAdd(albumId, assetId);
      } else {
        await _albumRemove(albumId, assetId);
      }
    }
    await _assetRepo.updateFavorite([assetId], rating > 0);
  }

  Future<void> execute(
    String assetId,
    SortAction action, {
    List<String> quickPickAlbumIds = const [],
    List<String> previousQuickPickAlbumIds = const [],
    int? starRating,
  }) async {
    final allAlbums = await _albumsApi.getAllAlbums();
    final newId = _kindId(allAlbums, 'new');

    switch (action) {
      case SortAction.delete:
        // Soft-delete (trash); force: false keeps it recoverable.
        await _assetRepo.delete([assetId], false);
        final rlIdDel = _kindId(allAlbums, 'review_later');
        if (rlIdDel != null) await _albumRemove(rlIdDel, assetId);
        if (newId != null) await _albumRemove(newId, assetId);

      case SortAction.reviewLater:
        final id = _kindId(allAlbums, 'review_later');
        if (id != null) await _albumAdd(id, assetId);
        if (newId != null) await _albumRemove(newId, assetId);

      case SortAction.sorted:
        // Remove from the review-later source album (photo may have come from
        // there).
        final rlIdSorted = _kindId(allAlbums, 'review_later');
        if (rlIdSorted != null) {
          await _albumRemove(rlIdSorted, assetId);
        }

        // Reconcile user (quick-pick) albums: add the selected ones, and in
        // edit mode remove any the user de-selected, so the asset ends up in
        // exactly the chosen albums.
        final target = quickPickAlbumIds.toSet();
        final previous = previousQuickPickAlbumIds.toSet();
        for (final qId in target) {
          await _albumAdd(qId, assetId);
        }
        for (final qId in previous.difference(target)) {
          await _albumRemove(qId, assetId);
        }

        // Star albums (exclusive). Skipped entirely when [starRating] is null
        // (e.g. the album-picker "Sort" button, which doesn't manage stars).
        if (starRating != null) {
          await _applyStarRating(allAlbums, assetId, starRating);
        }

        if (newId != null) await _albumRemove(newId, assetId);
    }
  }

  Future<void> undo(UndoRecord record) async {
    final allAlbums = await _albumsApi.getAllAlbums();
    final newId = _kindId(allAlbums, 'new');
    final assetId = record.asset.id;

    switch (record.action) {
      case SortAction.delete:
        await _assetRepo.restoreTrash([assetId]);
        if (newId != null) {
          await _albumAdd(newId, assetId);
        }

      case SortAction.reviewLater:
        final id = _kindId(allAlbums, 'review_later');
        if (id != null) await _albumRemove(id, assetId);
        if (newId != null) await _albumAdd(newId, assetId);

      case SortAction.sorted:
        final target = record.quickPickIds.toSet();
        final previous = record.previousQuickPickIds.toSet();
        // Reverse the user-album changes: remove what we added, restore what
        // we removed.
        for (final qId in target.difference(previous)) {
          await _albumRemove(qId, assetId);
        }
        for (final qId in previous.difference(target)) {
          await _albumAdd(qId, assetId);
        }

        // Restore the previous star rating if this sort changed it.
        if (record.starRating != record.previousStarRating) {
          await _applyStarRating(allAlbums, assetId, record.previousStarRating);
        }

        // Put it back in _New only if it came from there.
        if (record.wasInNew && newId != null) {
          await _albumAdd(newId, assetId);
        }
    }
  }
}

final sortActionServiceProvider = Provider<SortActionService>(
  (ref) => SortActionService(
    ref.watch(assetApiRepositoryProvider),
    ref.watch(albumApiRepositoryProvider),
    ref.watch(apiServiceProvider).albumsApi,
    ref.watch(remoteAlbumRepository),
  ),
);
