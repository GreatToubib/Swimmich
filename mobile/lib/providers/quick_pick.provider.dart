import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';

// ─── Storage keys ───────────────────────────────────────────────────────────

const _kPinnedKey = 'swimmich.quickpick.pinned';
const _kMruKey = 'swimmich.quickpick.mru';
const _kMaxMruAge = Duration(days: 30);
const _kMruSlots = 4;
const _kPinnedSlots = 4;

// ─── Models ─────────────────────────────────────────────────────────────────

class QuickPickMru {
  const QuickPickMru({required this.albumId, required this.lastUsed});

  final String albumId;
  final DateTime lastUsed;

  Map<String, dynamic> toJson() => {
        'albumId': albumId,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory QuickPickMru.fromJson(Map<String, dynamic> json) => QuickPickMru(
        albumId: json['albumId'] as String,
        lastUsed: DateTime.parse(json['lastUsed'] as String),
      );
}

/// A resolved chip entry — always has an albumId.
typedef QuickPickChip = ({String albumId, bool isPinned});

class QuickPickState {
  const QuickPickState({
    required this.pinned,
    required this.mru,
    required this.selected,
  });

  /// Exactly [_kPinnedSlots] entries; null means the slot is empty.
  final List<String?> pinned;

  /// Up to [_kMruSlots] most-recently-used albums, excluding pinned, sorted by
  /// [lastUsed] descending.
  final List<QuickPickMru> mru;

  /// Album IDs that are currently toggled ON (multi-select).
  final Set<String> selected;

  /// The chips to display: first the [_kPinnedSlots] pinned slots (may be null
  /// for empty), then up to [_kMruSlots] MRU entries, padded with nulls.
  List<QuickPickChip?> get chips {
    final result = <QuickPickChip?>[];
    for (final id in pinned) {
      result.add(id != null ? (albumId: id, isPinned: true) : null);
    }
    for (final m in mru) {
      result.add((albumId: m.albumId, isPinned: false));
    }
    // Pad to 6 so the row always has 6 slots.
    while (result.length < _kPinnedSlots + _kMruSlots) {
      result.add(null);
    }
    return result;
  }

  QuickPickState copyWith({
    List<String?>? pinned,
    List<QuickPickMru>? mru,
    Set<String>? selected,
  }) =>
      QuickPickState(
        pinned: pinned ?? this.pinned,
        mru: mru ?? this.mru,
        selected: selected ?? this.selected,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class QuickPickNotifier extends StateNotifier<QuickPickState> {
  QuickPickNotifier(this._storage)
      : super(
          const QuickPickState(
            pinned: [null, null, null, null],
            mru: [],
            selected: {},
          ),
        ) {
    _load();
  }

  final SecureStorageRepository _storage;

  // ── Initialise from secure storage ────────────────────────────────────────

  Future<void> _load() async {
    final pinnedRaw = await _storage.read(_kPinnedKey);
    final mruRaw = await _storage.read(_kMruKey);

    // Pinned: comma-separated, [_kPinnedSlots] entries, empty string = null.
    List<String?> pinned = List<String?>.filled(_kPinnedSlots, null);
    if (pinnedRaw != null && pinnedRaw.isNotEmpty) {
      final parts = pinnedRaw.split(',');
      for (int i = 0; i < _kPinnedSlots && i < parts.length; i++) {
        pinned[i] = parts[i].isEmpty ? null : parts[i];
      }
    }

    // MRU: JSON array, prune old entries.
    List<QuickPickMru> mru = [];
    if (mruRaw != null && mruRaw.isNotEmpty) {
      try {
        final list = jsonDecode(mruRaw) as List<dynamic>;
        final cutoff = DateTime.now().subtract(_kMaxMruAge);
        mru = list
            .map((e) => QuickPickMru.fromJson(e as Map<String, dynamic>))
            .where((m) => m.lastUsed.isAfter(cutoff))
            .toList()
          ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        // Remove any MRU entry that is now a pinned album.
        mru = mru.where((m) => !pinned.contains(m.albumId)).take(_kMruSlots).toList();
      } catch (_) {
        // Corrupt storage — start fresh.
        mru = [];
      }
    }

    state = state.copyWith(pinned: pinned, mru: mru);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Toggle an album chip on or off.
  void toggle(String albumId) {
    final next = Set<String>.from(state.selected);
    if (next.contains(albumId)) {
      next.remove(albumId);
    } else {
      next.add(albumId);
    }
    state = state.copyWith(selected: next);
  }

  /// Clear the current selection (call after a successful sort action).
  void clearSelection() => state = state.copyWith(selected: {});

  /// Set or clear a pinned slot (slot 0-2).
  Future<void> setPinned(int slot, String? albumId) async {
    assert(slot >= 0 && slot < _kPinnedSlots);
    final next = List<String?>.from(state.pinned);
    next[slot] = albumId;
    // Evict from MRU if now pinned.
    final mru = state.mru.where((m) => m.albumId != albumId).toList();
    state = state.copyWith(pinned: next, mru: mru);
    await _persist();
  }

  /// Remove pinned/MRU references to albums that no longer exist on the server.
  /// [existingIds] is the set of live album ids. Deleted pinned slots become
  /// empty; deleted MRU entries are dropped. No-op when nothing changed.
  Future<void> pruneDeleted(Set<String> existingIds) async {
    final pinned = state.pinned
        .map((id) => (id != null && existingIds.contains(id)) ? id : null)
        .toList();
    final mru =
        state.mru.where((m) => existingIds.contains(m.albumId)).toList();

    final pinnedChanged = !_listEquals(pinned, state.pinned);
    final mruChanged = mru.length != state.mru.length;
    if (!pinnedChanged && !mruChanged) return;

    // Also drop any now-dangling ids from the live selection.
    final selected =
        state.selected.where(existingIds.contains).toSet();

    state = state.copyWith(pinned: pinned, mru: mru, selected: selected);
    await _persist();
  }

  static bool _listEquals(List<String?> a, List<String?> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Record usage of the given album IDs (call after a successful sort action).
  void recordUsage(Iterable<String> albumIds) {
    if (albumIds.isEmpty) return;
    final now = DateTime.now();
    final cutoff = now.subtract(_kMaxMruAge);
    final pinnedSet = state.pinned.whereType<String>().toSet();

    // Update or insert each album.
    final mruMap = <String, QuickPickMru>{
      for (final m in state.mru) m.albumId: m,
    };
    for (final id in albumIds) {
      if (pinnedSet.contains(id)) continue; // pinned wins
      mruMap[id] = QuickPickMru(albumId: id, lastUsed: now);
    }

    // Prune and keep top-3 by lastUsed.
    final nextMru = mruMap.values
        .where((m) => m.lastUsed.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

    state = state.copyWith(mru: nextMru.take(_kMruSlots).toList());
    _persist();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _persist() async {
    // Pinned: comma-separated, empty string for null slot.
    final pinnedStr =
        state.pinned.map((id) => id ?? '').join(',');
    await _storage.write(_kPinnedKey, pinnedStr);

    // MRU: JSON.
    final mruJson =
        jsonEncode(state.mru.map((m) => m.toJson()).toList());
    await _storage.write(_kMruKey, mruJson);
  }
}

final quickPickProvider =
    StateNotifierProvider<QuickPickNotifier, QuickPickState>(
  (ref) => QuickPickNotifier(ref.watch(secureStorageRepositoryProvider)),
);
