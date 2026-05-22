import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/repositories/asset_media.repository.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

/// Holds device-asset ids whose local (phone) copy the user chose to delete
/// while sorting. Deletions are batched and flushed together so the OS shows a
/// single trash-confirmation dialog instead of one per swipe.
///
/// In-memory only — if the app is killed before a flush, the local copies
/// simply remain (they are safely in the cloud); the user can re-sort.
class LocalDeleteQueueNotifier extends StateNotifier<Set<String>> {
  LocalDeleteQueueNotifier(this._ref) : super(const {});

  final Ref _ref;
  final _log = Logger('LocalDeleteQueue');
  bool _flushing = false;

  void add(String localId) => state = {...state, localId};

  void remove(String localId) {
    if (!state.contains(localId)) return;
    state = state.where((id) => id != localId).toSet();
  }

  /// Flush the queue: request gallery permission if needed, then move the
  /// queued device files to the OS trash in one batched request. Guarded
  /// against re-entrancy and a no-op when empty.
  Future<void> flush() async {
    if (_flushing) return;
    final ids = state.toList();
    if (ids.isEmpty) return;
    _flushing = true;
    try {
      final permNotifier = _ref.read(galleryPermissionNotifier.notifier);
      var status = _ref.read(galleryPermissionNotifier);
      if (!(status.isGranted || status.isLimited)) {
        status = await permNotifier.requestGalleryPermission();
      }
      if (status.isGranted || status.isLimited) {
        await _ref.read(assetMediaRepositoryProvider).deleteAll(ids);
      } else {
        _log.warning('Gallery permission denied — skipping local delete');
      }
    } catch (e, st) {
      _log.warning('Local delete flush failed', e, st);
    } finally {
      // Drop the attempted ids regardless, to avoid re-prompting every trigger.
      state = state.difference(ids.toSet());
      _flushing = false;
    }
  }
}

final localDeleteQueueProvider =
    StateNotifierProvider<LocalDeleteQueueNotifier, Set<String>>(
  (ref) => LocalDeleteQueueNotifier(ref),
);
