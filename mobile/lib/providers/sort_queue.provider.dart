import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/sort_source_filter.provider.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class SortQueueState {
  const SortQueueState({
    required this.assets,
    this.currentIndex = 0,
    this.hasMore = true,
    this.totalToSort = 0,
  });

  final List<AssetResponseDto> assets;
  final int currentIndex;
  final bool hasMore;

  /// The session's starting count of cards to sort, summed from the source
  /// albums' assetCount. The live "left" count is derived from this minus how
  /// far the user has advanced, so the chip shows the true pile size (e.g.
  /// "150 left") rather than just the lazily-loaded batch. 0 = unknown.
  final int totalToSort;

  /// The asset currently at the top of the deck, or null when the queue is empty.
  AssetResponseDto? get current =>
      assets.isNotEmpty && currentIndex < assets.length
          ? assets[currentIndex]
          : null;

  /// How many cards remain from the current position to the end of the loaded list.
  int get remaining => assets.length - currentIndex;

  /// The true number of cards left to sort. Uses the source-album total when
  /// known (so lazy loading is invisible), falling back to the loaded count.
  int get leftToSort {
    if (totalToSort <= 0) return remaining;
    final left = totalToSort - currentIndex;
    return left < 0 ? 0 : left;
  }

  /// The asset directly behind the current card (for the peek effect), or null.
  AssetResponseDto? get nextAsset {
    final next = currentIndex + 1;
    return next < assets.length ? assets[next] : null;
  }

  SortQueueState copyWith({
    List<AssetResponseDto>? assets,
    int? currentIndex,
    bool? hasMore,
    int? totalToSort,
  }) =>
      SortQueueState(
        assets: assets ?? this.assets,
        currentIndex: currentIndex ?? this.currentIndex,
        hasMore: hasMore ?? this.hasMore,
        totalToSort: totalToSort ?? this.totalToSort,
      );
}

class SortQueueNotifier extends AsyncNotifier<SortQueueState> {
  static const _pageSize = 20;
  static const _prefetchAhead = 5;
  static const _loadMoreThreshold = 10;

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

  /// The album ids to pull from, in display-priority order: New first, then
  /// Review Later, then any other selected albums. The deck drains them in this
  /// order so cards appear grouped (all New, then Review, then the rest).
  ///
  /// Falls back to New + Review Later when the user selection is still empty
  /// (e.g. before async defaults have resolved).
  ///
  /// Also returns the true total number of cards to sort, summed from the
  /// source albums' `assetCount` (the only reliable count — Immich's search
  /// `total` is hardcoded to the page size). An asset in two source albums is
  /// double-counted, but that is rare and acceptable for a "left" indicator.
  Future<({List<String> ids, int total})> _resolveSources() async {
    final selected = ref.read(sortSourceAlbumsProvider);
    final allAlbums =
        await ref.read(apiServiceProvider).albumsApi.getAllAlbums() ?? [];

    String? kindId(String kind) => allAlbums
        .where((a) => a.systemKind == kind)
        .map((a) => a.id)
        .firstOrNull;

    final newId = kindId('new');
    final rlId = kindId('review_later');

    final List<String> ordered;
    if (selected.isEmpty) {
      ordered = [if (newId != null) newId, if (rlId != null) rlId];
    } else {
      ordered = <String>[];
      if (newId != null && selected.contains(newId)) ordered.add(newId);
      if (rlId != null && selected.contains(rlId)) ordered.add(rlId);
      for (final id in selected) {
        if (id != newId && id != rlId) ordered.add(id);
      }
    }

    final idSet = ordered.toSet();
    final total = allAlbums
        .where((a) => idSet.contains(a.id))
        .fold<int>(0, (sum, a) => sum + a.assetCount);

    return (ids: ordered, total: total);
  }

  Future<SortQueueState> _initLoad() async {
    final sources = await _resolveSources();
    if (sources.ids.isEmpty) {
      _log.warning('No source album ids found — system albums may not be provisioned yet');
      return const SortQueueState(assets: [], hasMore: false);
    }
    for (final id in sources.ids) {
      _cursors[id] = 1;
    }
    return _fetchNextBatch(const [], totalToSort: sources.total);
  }

  /// Fetches the next page from the highest-priority non-exhausted source album
  /// and appends new (deduped) assets to [existing]. Albums are drained one at
  /// a time in priority order (New → Review Later → others), so cards appear
  /// grouped by source rather than interleaved.
  ///
  /// Immich's metadata search treats multiple `albumIds` as an intersection,
  /// so each album is queried independently with its own page cursor.
  /// [_cursors] preserves insertion (= priority) order.
  Future<SortQueueState> _fetchNextBatch(
      List<AssetResponseDto> existing, {
      int totalToSort = 0,
      }) async {
    final seen = existing.map((a) => a.id).toSet();
    final merged = <AssetResponseDto>[...existing];
    final search = ref.read(apiServiceProvider).searchApi;

    try {
      // Keep pulling pages from the current top-priority album until it yields
      // at least one new card or every album is exhausted.
      while (_cursors.isNotEmpty && merged.length == existing.length) {
        final albumId = _cursors.keys.first;
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
      totalToSort: totalToSort,
    );
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Move to the next card. Transparently loads more assets when the buffer
  /// drops below [_loadMoreThreshold].
  Future<void> advance() async {
    final s = state.valueOrNull;
    if (s == null) return;

    final next = s.currentIndex + 1;

    // Transparently load the next batch when running low, and always await a
    // fetch before exposing a gap at the exact end of the loaded list — so the
    // deck never flashes the "all caught up" view while more cards exist.
    if (s.hasMore &&
        (next >= s.assets.length ||
            (s.assets.length - next) < _loadMoreThreshold)) {
      final updated =
          await _fetchNextBatch(s.assets, totalToSort: s.totalToSort);
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
