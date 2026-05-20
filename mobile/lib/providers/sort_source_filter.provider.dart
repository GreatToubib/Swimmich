import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';

/// The set of album IDs the sort deck pulls photos from.
///
/// Multiple albums are combined as a UNION (an asset from any selected album
/// appears in the deck). Immich's metadata search ANDs multiple albumIds, so
/// the sort queue queries each album separately and merges the results.
///
/// Defaults to New + Review Later, resolved from secure storage on first build.
/// An empty selection is treated as "use the defaults" by the queue, and the
/// picker prevents deselecting the last album.
class SortSourceAlbumsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _loadDefaults();
    return const {};
  }

  Future<void> _loadDefaults() async {
    final storage = ref.read(secureStorageRepositoryProvider);
    final newId =
        await storage.read(SwimmichSystemAlbum.newAssets.storageKey);
    final rlId =
        await storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
    final ids = <String>{
      if (newId != null) newId,
      if (rlId != null) rlId,
    };
    // Only seed defaults if the user hasn't already chosen anything.
    if (state.isEmpty && ids.isNotEmpty) state = ids;
  }

  /// Toggle an album in/out of the selection. Refuses to remove the last one.
  void toggle(String albumId) {
    final next = Set<String>.from(state);
    if (next.contains(albumId)) {
      if (next.length == 1) return; // keep at least one source
      next.remove(albumId);
    } else {
      next.add(albumId);
    }
    state = next;
  }

  void setAll(Set<String> ids) => state = ids;
}

final sortSourceAlbumsProvider =
    NotifierProvider<SortSourceAlbumsNotifier, Set<String>>(
  SortSourceAlbumsNotifier.new,
);
