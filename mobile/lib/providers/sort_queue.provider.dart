import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/sort_source_filter.provider.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class SortQueueState {
  const SortQueueState({
    required this.assets,
    this.currentIndex = 0,
    this.hasMore = true,
  });

  final List<AssetResponseDto> assets;
  final int currentIndex;
  final bool hasMore;

  /// The asset currently at the top of the deck, or null when the queue is empty.
  AssetResponseDto? get current =>
      assets.isNotEmpty && currentIndex < assets.length
          ? assets[currentIndex]
          : null;

  /// How many cards remain from the current position to the end of the loaded list.
  int get remaining => assets.length - currentIndex;

  /// The asset directly behind the current card (for the peek effect), or null.
  AssetResponseDto? get nextAsset {
    final next = currentIndex + 1;
    return next < assets.length ? assets[next] : null;
  }

  SortQueueState copyWith({
    List<AssetResponseDto>? assets,
    int? currentIndex,
    bool? hasMore,
  }) =>
      SortQueueState(
        assets: assets ?? this.assets,
        currentIndex: currentIndex ?? this.currentIndex,
        hasMore: hasMore ?? this.hasMore,
      );
}

class SortQueueNotifier extends AsyncNotifier<SortQueueState> {
  static const _pageSize = 20;
  static const _prefetchAhead = 5;
  static const _loadMoreThreshold = 5;

  /// Per-album page cursor (next page to fetch). An album removed from this map
  /// is exhausted (no more pages).
  final Map<String, int> _cursors = {};
  final _log = Logger('SortQueueNotifier');

  @override
  Future<SortQueueState> build() {
    // Auto-rebuild when the selected source albums change.
    ref.watch(sortSourceAlbumsProvider);
    _cursors.clear();
    return _initLoad();
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// The album ids to pull from. Falls back to New + Review Later when the user
  /// selection is still empty (e.g. before async defaults have resolved).
  Future<List<String>> _albumIds() async {
    final selected = ref.read(sortSourceAlbumsProvider);
    if (selected.isNotEmpty) return selected.toList();

    final storage = ref.read(secureStorageRepositoryProvider);
    final ids = <String>[];
    final newId =
        await storage.read(SwimmichSystemAlbum.newAssets.storageKey);
    final rlId =
        await storage.read(SwimmichSystemAlbum.reviewLater.storageKey);
    if (newId != null) ids.add(newId);
    if (rlId != null) ids.add(rlId);
    return ids;
  }

  Future<SortQueueState> _initLoad() async {
    final albumIds = await _albumIds();
    if (albumIds.isEmpty) {
      _log.warning('No source album ids found — bootstrap may not have run yet');
      return const SortQueueState(assets: [], hasMore: false);
    }
    for (final id in albumIds) {
      _cursors[id] = 1;
    }
    return _fetchNextBatch(const []);
  }

  /// Fetches the next page from every non-exhausted source album and merges
  /// the results into [existing] as a UNION (deduped by asset id).
  ///
  /// Immich's metadata search treats multiple `albumIds` as an intersection,
  /// so each album is queried independently with its own page cursor.
  Future<SortQueueState> _fetchNextBatch(
      List<AssetResponseDto> existing) async {
    final seen = existing.map((a) => a.id).toSet();
    final merged = <AssetResponseDto>[...existing];
    final search = ref.read(apiServiceProvider).searchApi;

    try {
      for (final albumId in _cursors.keys.toList()) {
        final page = _cursors[albumId]!;
        final resp = await search.searchAssets(
          MetadataSearchDto(
            albumIds: [albumId],
            page: page,
            size: _pageSize,
            withDeleted: false,
          ),
        );
        if (resp == null) {
          _cursors.remove(albumId);
          continue;
        }
        for (final asset in resp.assets.items) {
          if (seen.add(asset.id)) merged.add(asset);
        }
        if (resp.assets.nextPage == null) {
          _cursors.remove(albumId);
        } else {
          _cursors[albumId] = page + 1;
        }
      }
    } catch (e, st) {
      _log.severe('Failed to load sort queue assets', e, st);
      rethrow;
    }

    return SortQueueState(
      assets: merged,
      currentIndex: existing.isEmpty ? 0 : existing.length,
      hasMore: _cursors.isNotEmpty,
    );
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Move to the next card. Transparently loads more assets when the buffer
  /// drops below [_loadMoreThreshold].
  Future<void> advance() async {
    final s = state.valueOrNull;
    if (s == null) return;

    final next = s.currentIndex + 1;

    // Transparently load the next batch when running low.
    if (s.hasMore && (s.assets.length - next) < _loadMoreThreshold) {
      final updated = await _fetchNextBatch(s.assets);
      state = AsyncData(updated.copyWith(currentIndex: next));
      return;
    }

    state = AsyncData(s.copyWith(currentIndex: next));
  }

  /// Inserts an asset at the current position (front of the visible deck).
  /// Used by undo to make the un-done card immediately visible.
  void insertAtCurrent(AssetResponseDto asset) {
    final s = state.valueOrNull;
    if (s == null) return;
    final next = List<AssetResponseDto>.from(s.assets)
      ..insert(s.currentIndex, asset);
    state = AsyncData(s.copyWith(assets: next));
  }

  /// Rolls back a single [advance] call for optimistic-failure recovery.
  void revertAdvance() {
    final s = state.valueOrNull;
    if (s == null || s.currentIndex == 0) return;
    state = AsyncData(s.copyWith(currentIndex: s.currentIndex - 1));
  }

  /// Reset the queue and reload from the first page of every source album.
  Future<void> refresh() async {
    _cursors.clear();
    state = const AsyncLoading();
    state = AsyncData(await _initLoad());
  }

  /// Pre-warm the image cache for the next [_prefetchAhead] cards.
  void prefetchNext(BuildContext context) {
    final s = state.valueOrNull;
    if (s == null) return;
    final from = s.currentIndex + 1;
    final to = (from + _prefetchAhead).clamp(0, s.assets.length);
    for (int i = from; i < to; i++) {
      final asset = s.assets[i];
      precacheImage(
        RemoteImageProvider.thumbnail(
          assetId: asset.id,
          thumbhash: asset.thumbhash ?? '',
        ),
        context,
      );
    }
  }
}

final sortQueueProvider =
    AsyncNotifierProvider<SortQueueNotifier, SortQueueState>(
        SortQueueNotifier.new);
