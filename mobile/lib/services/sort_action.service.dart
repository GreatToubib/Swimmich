import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_album.repository.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';
import 'package:openapi/api.dart';

enum SortAction { delete, reviewLater, sorted }

class UndoRecord {
  const UndoRecord({
    required this.asset,
    required this.action,
    required this.quickPickIds,
    this.starRating = 0,
  });

  final AssetResponseDto asset;
  final SortAction action;
  final List<String> quickPickIds;
  final int starRating; // 0 = none, 1–3 = stars selected at sort time
}

/// Executes the three sort-deck actions against the Immich API.
///
/// All operations are idempotent on duplicate calls (adding to an album
/// where the asset already lives is a no-op on the server).
class SortActionService {
  const SortActionService(
    this._assetRepo,
    this._albumRepo,
    this._storage,
    this._driftAlbumRepo,
  );

  final AssetApiRepository _assetRepo;
  final AlbumApiRepository _albumRepo;
  final SecureStorageRepository _storage;
  final DriftRemoteAlbumRepository _driftAlbumRepo;

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

  Future<void> execute(
    String assetId,
    SortAction action, {
    List<String> quickPickAlbumIds = const [],
    int starRating = 0,
  }) async {
    final newId =
        await _storage.read(SwimmichSystemAlbum.newAssets.storageKey);

    switch (action) {
      case SortAction.delete:
        // Soft-delete (trash); force: false keeps it recoverable.
        await _assetRepo.delete([assetId], false);
        final rlIdDel =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (rlIdDel != null) await _albumRemove(rlIdDel, assetId);
        if (newId != null) await _albumRemove(newId, assetId);

      case SortAction.reviewLater:
        final id =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (id != null) await _albumAdd(id, assetId);
        if (newId != null) await _albumRemove(newId, assetId);

      case SortAction.sorted:
        // Remove from both source albums (photo may have come from either).
        final rlIdSorted =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (rlIdSorted != null) {
          await _albumRemove(rlIdSorted, assetId);
        }
        for (final qId in quickPickAlbumIds) {
          await _albumAdd(qId, assetId);
        }
        // Star albums — cumulative: 2★ adds to both _1 Star and _2 Star.
        if (starRating >= 1) {
          final oneId =
              await _storage.read(SwimmichSystemAlbum.oneStar.storageKey);
          if (oneId != null) await _albumAdd(oneId, assetId);
        }
        if (starRating >= 2) {
          final twoId =
              await _storage.read(SwimmichSystemAlbum.twoStar.storageKey);
          if (twoId != null) await _albumAdd(twoId, assetId);
        }
        if (starRating >= 3) {
          final threeId =
              await _storage.read(SwimmichSystemAlbum.threeStar.storageKey);
          if (threeId != null) await _albumAdd(threeId, assetId);
        }
        if (starRating > 0) {
          await _assetRepo.updateFavorite([assetId], true);
        }
        if (newId != null) await _albumRemove(newId, assetId);
    }
  }

  Future<void> undo(UndoRecord record) async {
    final newId = await _storage.read(SwimmichSystemAlbum.newAssets.storageKey);

    switch (record.action) {
      case SortAction.delete:
        await _assetRepo.restoreTrash([record.asset.id]);
        if (newId != null) {
          await _albumAdd(newId, record.asset.id);
        }

      case SortAction.reviewLater:
        final id =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (id != null) await _albumRemove(id, record.asset.id);
        if (newId != null) await _albumAdd(newId, record.asset.id);

      case SortAction.sorted:
        for (final qId in record.quickPickIds) {
          await _albumRemove(qId, record.asset.id);
        }
        // Reverse star albums.
        if (record.starRating >= 1) {
          final oneId =
              await _storage.read(SwimmichSystemAlbum.oneStar.storageKey);
          if (oneId != null) {
            await _albumRemove(oneId, record.asset.id);
          }
        }
        if (record.starRating >= 2) {
          final twoId =
              await _storage.read(SwimmichSystemAlbum.twoStar.storageKey);
          if (twoId != null) {
            await _albumRemove(twoId, record.asset.id);
          }
        }
        if (record.starRating >= 3) {
          final threeId =
              await _storage.read(SwimmichSystemAlbum.threeStar.storageKey);
          if (threeId != null) {
            await _albumRemove(threeId, record.asset.id);
          }
        }
        if (record.starRating > 0) {
          await _assetRepo.updateFavorite([record.asset.id], false);
        }
        if (newId != null) await _albumAdd(newId, record.asset.id);
    }
  }
}

final sortActionServiceProvider = Provider<SortActionService>(
  (ref) => SortActionService(
    ref.watch(assetApiRepositoryProvider),
    ref.watch(albumApiRepositoryProvider),
    ref.watch(secureStorageRepositoryProvider),
    ref.watch(remoteAlbumRepository),
  ),
);
