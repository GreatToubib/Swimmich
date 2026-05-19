import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';

enum SortAction { delete, reviewLater, sorted }

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
}

final sortActionServiceProvider = Provider<SortActionService>(
  (ref) => SortActionService(
    ref.watch(assetApiRepositoryProvider),
    ref.watch(albumApiRepositoryProvider),
    ref.watch(secureStorageRepositoryProvider),
  ),
);
