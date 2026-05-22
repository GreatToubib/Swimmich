import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';

const _kDeleteLocalKey = 'swimmich.sort.deleteLocalOnSort';

/// Whether, by default, swiping a locally-stored card also queues its local
/// (device) copy for deletion. Persisted; defaults to ON. Each card seeds its
/// own trash toggle from this value and can override it per card.
class DeleteLocalOnSortNotifier extends StateNotifier<bool> {
  DeleteLocalOnSortNotifier(this._storage) : super(true) {
    _load();
  }

  final SecureStorageRepository _storage;

  Future<void> _load() async {
    final raw = await _storage.read(_kDeleteLocalKey);
    if (raw != null) state = raw == 'true';
  }

  Future<void> set(bool value) async {
    state = value;
    await _storage.write(_kDeleteLocalKey, value ? 'true' : 'false');
  }
}

final deleteLocalOnSortProvider =
    StateNotifierProvider<DeleteLocalOnSortNotifier, bool>(
  (ref) => DeleteLocalOnSortNotifier(ref.watch(secureStorageRepositoryProvider)),
);
