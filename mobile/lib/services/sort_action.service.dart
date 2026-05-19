import 'package:hooks_riverpod/hooks_riverpod.dart';
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
  const SortActionService(this._assetRepo, this._albumRepo, this._storage);

  final AssetApiRepository _assetRepo;
  final AlbumApiRepository _albumRepo;
  final SecureStorageRepository _storage;

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
        if (rlIdDel != null) await _albumRepo.removeAssets(rlIdDel, [assetId]);
        if (newId != null) await _albumRepo.removeAssets(newId, [assetId]);

      case SortAction.reviewLater:
        final id =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (id != null) await _albumRepo.addAssets(id, [assetId]);
        if (newId != null) await _albumRepo.removeAssets(newId, [assetId]);

      case SortAction.sorted:
        // Remove from both source albums (photo may have come from either).
        final rlIdSorted =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (rlIdSorted != null) {
          await _albumRepo.removeAssets(rlIdSorted, [assetId]);
        }
        for (final qId in quickPickAlbumIds) {
          await _albumRepo.addAssets(qId, [assetId]);
        }
        // Star albums — cumulative: 2★ adds to both _1 Star and _2 Star.
        if (starRating >= 1) {
          final oneId =
              await _storage.read(SwimmichSystemAlbum.oneStar.storageKey);
          if (oneId != null) await _albumRepo.addAssets(oneId, [assetId]);
        }
        if (starRating >= 2) {
          final twoId =
              await _storage.read(SwimmichSystemAlbum.twoStar.storageKey);
          if (twoId != null) await _albumRepo.addAssets(twoId, [assetId]);
        }
        if (starRating >= 3) {
          final threeId =
              await _storage.read(SwimmichSystemAlbum.threeStar.storageKey);
          if (threeId != null) await _albumRepo.addAssets(threeId, [assetId]);
        }
        if (starRating > 0) {
          await _assetRepo.updateFavorite([assetId], true);
        }
        if (newId != null) await _albumRepo.removeAssets(newId, [assetId]);
    }
  }

  Future<void> undo(UndoRecord record) async {
    final newId = await _storage.read(SwimmichSystemAlbum.newAssets.storageKey);

    switch (record.action) {
      case SortAction.delete:
        await _assetRepo.restoreTrash([record.asset.id]);
        if (newId != null) {
          await _albumRepo.addAssets(newId, [record.asset.id]);
        }

      case SortAction.reviewLater:
        final id =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (id != null) await _albumRepo.removeAssets(id, [record.asset.id]);
        if (newId != null) await _albumRepo.addAssets(newId, [record.asset.id]);

      case SortAction.sorted:
        for (final qId in record.quickPickIds) {
          await _albumRepo.removeAssets(qId, [record.asset.id]);
        }
        // Reverse star albums.
        if (record.starRating >= 1) {
          final oneId =
              await _storage.read(SwimmichSystemAlbum.oneStar.storageKey);
          if (oneId != null) {
            await _albumRepo.removeAssets(oneId, [record.asset.id]);
          }
        }
        if (record.starRating >= 2) {
          final twoId =
              await _storage.read(SwimmichSystemAlbum.twoStar.storageKey);
          if (twoId != null) {
            await _albumRepo.removeAssets(twoId, [record.asset.id]);
          }
        }
        if (record.starRating >= 3) {
          final threeId =
              await _storage.read(SwimmichSystemAlbum.threeStar.storageKey);
          if (threeId != null) {
            await _albumRepo.removeAssets(threeId, [record.asset.id]);
          }
        }
        if (record.starRating > 0) {
          await _assetRepo.updateFavorite([record.asset.id], false);
        }
        if (newId != null) await _albumRepo.addAssets(newId, [record.asset.id]);
    }
  }
}

final sortActionServiceProvider = Provider<SortActionService>(
  (ref) => SortActionService(
    ref.watch(assetApiRepositoryProvider),
    ref.watch(albumApiRepositoryProvider),
    ref.watch(secureStorageRepositoryProvider),
  ),
);
