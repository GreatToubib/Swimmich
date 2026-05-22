import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
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

  /// The number of cards left to sort. Derived from the lazily-loaded buffer;
  /// it grows as more pages stream in, so it is a lower bound while [hasMore].
  int get leftToSort => remaining;

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
  static const _loadMoreThreshold = 10;

  /// The triage statuses the deck drains, in display-priority order: freshly
  /// added (`new`) photos first, then anything explicitly deferred for review.
  static const _sources = <SortStatus>[
    SortStatus.new_,
    SortStatus.reviewLater,
  ];

  /// Index into [_sources] of the status currently being drained, plus the next
  /// page to fetch for it. When [_sourceIndex] runs past the list, the deck is
  /// exhausted.
  int _sourceIndex = 0;
  int _page = 1;
  final _log = Logger('SortQueueNotifier');

  @override
  Future<SortQueueState> build() {
    _sourceIndex = 0;
    _page = 1;
    return _fetchNextBatch(const []);
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Fetches the next page from the highest-priority non-exhausted status and
  /// appends new (deduped) assets to [existing]. Statuses are drained one at a
  /// time in priority order, so cards appear grouped by status.
  Future<SortQueueState> _fetchNextBatch(List<AssetResponseDto> existing) async {
    final seen = existing.map((a) => a.id).toSet();
    final merged = <AssetResponseDto>[...existing];
    final search = ref.read(apiServiceProvider).searchApi;

    try {
      // Keep pulling pages from the current top-priority status until it yields
      // at least one new card or every status is exhausted.
      while (_sourceIndex < _sources.length &&
          merged.length == existing.length) {
        final resp = await search.searchAssets(
          MetadataSearchDto(
            sortStatus: _sources[_sourceIndex],
            page: _page,
            size: _pageSize,
            withDeleted: false,
            // EXIF carries the native star rating used to prefill the card.
            withExif: true,
          ),
        );
        if (resp == null) {
          _advanceSource();
          continue;
        }
        for (final asset in resp.assets.items) {
          if (seen.add(asset.id)) merged.add(asset);
        }
        if (resp.assets.nextPage == null) {
          _advanceSource();
        } else {
          _page += 1;
        }
      }
    } catch (e, st) {
      _log.severe('Failed to load sort queue assets', e, st);
      rethrow;
    }

    return SortQueueState(
      assets: merged,
      currentIndex: existing.isEmpty ? 0 : existing.length,
      hasMore: _sourceIndex < _sources.length,
    );
  }

  void _advanceSource() {
    _sourceIndex += 1;
    _page = 1;
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

  /// Reset the queue and reload from the first page of the highest-priority
  /// status.
  Future<void> refresh() async {
    _sourceIndex = 0;
    _page = 1;
    state = const AsyncLoading();
    state = AsyncData(await _fetchNextBatch(const []));
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
