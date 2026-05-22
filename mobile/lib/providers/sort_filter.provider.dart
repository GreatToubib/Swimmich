import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:openapi/api.dart';

// ─── Storage key ──────────────────────────────────────────────────────────────

const _kFilterKey = 'swimmich.sort.filter';

// ─── State ──────────────────────────────────────────────────────────────────

/// What enters the sort deck. Two sections combined with AND:
///   (status ∈ [statuses]) AND (in no album if [noAlbum] OR in any of [albumIds])
/// Within each section the options are OR-ed. Each section must keep ≥1 option.
class SortFilterState {
  const SortFilterState({
    required this.statuses,
    required this.noAlbum,
    required this.albumIds,
  });

  final Set<SortStatus> statuses;
  final bool noAlbum;
  final Set<String> albumIds;

  /// Number of selected options across both sections (for the header badge).
  int get selectionCount =>
      statuses.length + (noAlbum ? 1 : 0) + albumIds.length;

  /// True while the album section selects at least one option.
  bool get hasAlbumSelection => noAlbum || albumIds.isNotEmpty;

  SortFilterState copyWith({
    Set<SortStatus>? statuses,
    bool? noAlbum,
    Set<String>? albumIds,
  }) =>
      SortFilterState(
        statuses: statuses ?? this.statuses,
        noAlbum: noAlbum ?? this.noAlbum,
        albumIds: albumIds ?? this.albumIds,
      );

  static SortFilterState get defaults => const SortFilterState(
        statuses: {SortStatus.new_, SortStatus.reviewLater},
        noAlbum: true,
        albumIds: {},
      );

  Map<String, dynamic> toJson() => {
        'statuses': statuses.map((s) => s.value).toList(),
        'noAlbum': noAlbum,
        'albumIds': albumIds.toList(),
      };

  factory SortFilterState.fromJson(Map<String, dynamic> json) {
    final statuses = (json['statuses'] as List<dynamic>? ?? const [])
        .map((e) => SortStatus.fromJson(e))
        .whereType<SortStatus>()
        .toSet();
    return SortFilterState(
      statuses: statuses.isEmpty ? {SortStatus.new_} : statuses,
      noAlbum: json['noAlbum'] as bool? ?? true,
      albumIds:
          (json['albumIds'] as List<dynamic>? ?? const []).cast<String>().toSet(),
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class SortFilterNotifier extends StateNotifier<SortFilterState> {
  SortFilterNotifier(this._storage) : super(SortFilterState.defaults) {
    _loaded = _load();
  }

  final SecureStorageRepository _storage;

  late final Future<void> _loaded;
  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    final raw = await _storage.read(_kFilterKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = SortFilterState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt storage — keep defaults.
    }
  }

  /// Toggle a sort status; refuses to remove the last selected status.
  void toggleStatus(SortStatus status) {
    final next = Set<SortStatus>.from(state.statuses);
    if (next.contains(status)) {
      if (next.length == 1) return; // keep ≥1 status
      next.remove(status);
    } else {
      next.add(status);
    }
    state = state.copyWith(statuses: next);
    _persist();
  }

  /// Toggle the "No album" option; refuses to empty the album section.
  void toggleNoAlbum() {
    if (state.noAlbum && state.albumIds.isEmpty) return; // keep ≥1 album option
    state = state.copyWith(noAlbum: !state.noAlbum);
    _persist();
  }

  /// Toggle a specific album; refuses to empty the album section.
  void toggleAlbum(String albumId) {
    final next = Set<String>.from(state.albumIds);
    if (next.contains(albumId)) {
      if (next.length == 1 && !state.noAlbum) return; // keep ≥1 album option
      next.remove(albumId);
    } else {
      next.add(albumId);
    }
    state = state.copyWith(albumIds: next);
    _persist();
  }

  /// Drop album ids that no longer exist on the server.
  void pruneAlbums(Set<String> existingIds) {
    final kept = state.albumIds.where(existingIds.contains).toSet();
    if (kept.length == state.albumIds.length) return;
    // Never let the album section go empty.
    state = state.copyWith(
      albumIds: kept,
      noAlbum: kept.isEmpty ? true : state.noAlbum,
    );
    _persist();
  }

  Future<void> _persist() =>
      _storage.write(_kFilterKey, jsonEncode(state.toJson()));
}

final sortFilterProvider =
    StateNotifierProvider<SortFilterNotifier, SortFilterState>(
  (ref) => SortFilterNotifier(ref.watch(secureStorageRepositoryProvider)),
);
