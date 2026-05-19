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
  });

  final AssetResponseDto asset;
  final SortAction action;
  final List<String> quickPickIds;
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
  }) async {
    final newId =
        await _storage.read(SwimmichSystemAlbum.newAssets.storageKey);

    switch (action) {
      case SortAction.delete:
        // Soft-delete (trash); force: false keeps it recoverable.
        await _assetRepo.delete([assetId], false);
        if (newId != null) await _albumRepo.removeAssets(newId, [assetId]);

      case SortAction.reviewLater:
        final id =
            await _storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
        if (id != null) await _albumRepo.addAssets(id, [assetId]);
        if (newId != null) await _albumRepo.removeAssets(newId, [assetId]);

      case SortAction.sorted:
        final id =
            await _storage.read(SwimmichSystemAlbum.sorted.storageKey);
        if (id != null) await _albumRepo.addAssets(id, [assetId]);
        for (final qId in quickPickAlbumIds) {
          await _albumRepo.addAssets(qId, [assetId]);
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
        final id = await _storage.read(SwimmichSystemAlbum.sorted.storageKey);
        if (id != null) await _albumRepo.removeAssets(id, [record.asset.id]);
        for (final qId in record.quickPickIds) {
          await _albumRepo.removeAssets(qId, [record.asset.id]);
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
