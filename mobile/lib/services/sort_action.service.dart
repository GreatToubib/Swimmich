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
    this.favorite = false,
    this.previousFavorite = false,
    this.previousSortStatus = SortStatus.new_,
  });

  final AssetResponseDto asset;
  final SortAction action;

  /// Quick-pick (user) albums the asset was sorted INTO.
  final List<String> quickPickIds;

  /// Quick-pick (user) albums the asset was in BEFORE the sort (edit mode).
  final List<String> previousQuickPickIds;

  /// Star rating applied by this sort (0 = none, 1–5).
  final int starRating;

  /// Star rating the asset had before this sort.
  final int previousStarRating;

  /// Favourite flag applied by this sort.
  final bool favorite;

  /// Favourite flag the asset had before this sort.
  final bool previousFavorite;

  /// The asset's triage status before this sort, so undo can restore it.
  final SortStatus previousSortStatus;
}

/// Executes the three sort-deck actions against native Immich asset fields:
/// `sortStatus` (triage), `rating` (1–5 stars), `isFavorite`, plus optional
/// membership in user-curated albums. No system/proxy albums are involved.
class SortActionService {
  const SortActionService(
    this._assetRepo,
    this._albumRepo,
    this._driftAlbumRepo,
  );

  final AssetApiRepository _assetRepo;
  final AlbumApiRepository _albumRepo;
  final DriftRemoteAlbumRepository _driftAlbumRepo;

  /// Adds an asset to a user album on the server, then mirrors the change into
  /// the local Drift DB so the Albums view reflects it without a full re-sync.
  /// The local mirror is best-effort and must never fail the server operation.
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

  /// Reconciles the asset's user-album membership to exactly [target]:
  /// adds the newly selected albums and removes any that were de-selected.
  Future<void> _reconcileAlbums(
    String assetId,
    Set<String> target,
    Set<String> previous,
  ) async {
    for (final id in target) {
      await _albumAdd(id, assetId);
    }
    for (final id in previous.difference(target)) {
      await _albumRemove(id, assetId);
    }
  }

  Future<void> execute(
    String assetId,
    SortAction action, {
    List<String> quickPickAlbumIds = const [],
    List<String> previousQuickPickAlbumIds = const [],
    int? starRating,
    bool favorite = false,
  }) async {
    switch (action) {
      case SortAction.delete:
        // Soft-delete (trash); force: false keeps it recoverable.
        await _assetRepo.delete([assetId], false);

      case SortAction.reviewLater:
        await _assetRepo.setSortStatus(assetId, SortStatus.reviewLater);

      case SortAction.sorted:
        // Keep: native triage status + rating + favourite, plus optional
        // membership in user-curated albums. Any of these may be a no-op.
        await _assetRepo.setSortStatus(
          assetId,
          SortStatus.kept,
          rating: starRating,
        );
        await _assetRepo.updateFavorite([assetId], favorite);
        await _reconcileAlbums(
          assetId,
          quickPickAlbumIds.toSet(),
          previousQuickPickAlbumIds.toSet(),
        );
    }
  }

  Future<void> undo(UndoRecord record) async {
    final assetId = record.asset.id;

    switch (record.action) {
      case SortAction.delete:
        await _assetRepo.restoreTrash([assetId]);

      case SortAction.reviewLater:
        await _assetRepo.setSortStatus(assetId, record.previousSortStatus);

      case SortAction.sorted:
        // Restore the previous triage status, rating and favourite.
        await _assetRepo.setSortStatus(
          assetId,
          record.previousSortStatus,
          rating: record.previousStarRating,
        );
        await _assetRepo.updateFavorite([assetId], record.previousFavorite);
        // Reverse the user-album changes: remove what we added, restore what
        // we removed.
        final target = record.quickPickIds.toSet();
        final previous = record.previousQuickPickIds.toSet();
        await _reconcileAlbums(assetId, previous, target);
    }
  }
}

final sortActionServiceProvider = Provider<SortActionService>(
  (ref) => SortActionService(
    ref.watch(assetApiRepositoryProvider),
    ref.watch(albumApiRepositoryProvider),
    ref.watch(remoteAlbumRepository),
  ),
);
