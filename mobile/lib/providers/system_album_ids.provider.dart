import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';

/// Remote IDs of all Swimmich system albums, loaded from secure storage.
///
/// Used by album pickers to filter system albums regardless of their display
/// name (e.g. emoji star albums that don't start with '_').
final systemAlbumIdsProvider = FutureProvider<Set<String>>((ref) async {
  final storage = ref.watch(secureStorageRepositoryProvider);
  final ids = <String>{};
  for (final album in SwimmichSystemAlbum.values) {
    final id = await storage.read(album.storageKey);
    if (id != null) ids.add(id);
  }
  return ids;
});
