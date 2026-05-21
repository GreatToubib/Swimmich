import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';

/// Remote IDs of all Swimmich system albums, derived from the server's
/// systemKind field so identity is stable even after renaming.
final systemAlbumIdsProvider = FutureProvider<Set<String>>((ref) async {
  final albums = await ref.watch(apiServiceProvider).albumsApi.getAllAlbums();
  return (albums ?? [])
      .where((a) => a.systemKind != null)
      .map((a) => a.id)
      .toSet();
});
