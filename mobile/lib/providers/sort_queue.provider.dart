import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/sort_filter.provider.dart';
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

/// One query stream: a (status × album-option) combination. [noAlbum] true means
/// "not in any album"; otherwise [albumId] is a specific album. Immich ANDs
/// `albumIds`, so unions across albums are achieved with separate specs.
class _SourceSpec {
  _SourceSpec({required this.status, this.albumId, this.noAlbum = false});
  final SortStatus status;
  final String? albumId;
  final bool noAlbum;
}

class SortQueueNotifier extends AsyncNotifier<SortQueueState> {
  static const _pageSize = 20;
  static const _prefetchAhead = 5;
  static const _loadMoreThreshold = 10;

  /// Query specs derived from the active filter, drained one at a time.
  List<_SourceSpec> _specs = const [];
  int _specIndex = 0;
  int _page = 1;
  final _log = Logger('SortQueueNotifier');

  @override
  Future<SortQueueState> build() {
    // Rebuild whenever the source filter changes.
    final filter = ref.watch(sortFilterProvider);
    _specs = _buildSpecs(filter);
    _specIndex = 0;
    _page = 1;
    return _fetchNextBatch(const []);
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Cross-product of selected statuses × selected album options. Statuses are
  /// ordered new → review_later → kept; the "No album" option comes before
  /// specific albums so unsorted-and-unfiled photos surface first.
  List<_SourceSpec> _buildSpecs(SortFilterState filter) {
    const statusOrder = [
      SortStatus.new_,
      SortStatus.reviewLater,
      SortStatus.kept,
    ];
    final statuses = statusOrder.where(filter.statuses.contains).toList();
    final specs = <_SourceSpec>[];
    for (final status in statuses) {
      if (filter.noAlbum) {
        specs.add(_SourceSpec(status: status, noAlbum: true));
      }
      for (final albumId in filter.albumIds) {
        specs.add(_SourceSpec(status: status, albumId: albumId));
      }
    }
    return specs;
  }

  /// Fetches the next page from the highest-priority non-exhausted spec and
  /// appends new (deduped) assets to [existing].
  Future<SortQueueState> _fetchNextBatch(List<AssetResponseDto> existing) async {
    final seen = existing.map((a) => a.id).toSet();
    final merged = <AssetResponseDto>[...existing];
    final search = ref.read(apiServiceProvider).searchApi;

    try {
      while (_specIndex < _specs.length && merged.length == existing.length) {
        final spec = _specs[_specIndex];
        final resp = await search.searchAssets(
          MetadataSearchDto(
            sortStatus: Optional.present(spec.status),
            albumIds: Optional.present(spec.albumId != null ? [spec.albumId!] : const []),
            // Must stay absent (omitted) rather than an explicit null when the
            // filter is off: v3's client serialises Optional.present(null) as
            // JSON null, which is a different query from omitting the field.
            isNotInAlbum: spec.noAlbum ? const Optional.present(true) : const Optional.absent(),
            page: Optional.present(_page),
            size: Optional.present(_pageSize),
            withDeleted: const Optional.present(false),
            // EXIF carries the native star rating used to prefill the card.
            withExif: const Optional.present(true),
          ),
        );
        if (resp == null) {
          _advanceSpec();
          continue;
        }
        for (final asset in resp.assets.items) {
          if (seen.add(asset.id)) merged.add(asset);
        }
        if (resp.assets.nextPage == null) {
          _advanceSpec();
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
      hasMore: _specIndex < _specs.length,
    );
  }

  void _advanceSpec() {
    _specIndex += 1;
    _page = 1;
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Move to the next card. Transparently loads more assets when the buffer
  /// drops below [_loadMoreThreshold].
  Future<void> advance() async {
    final s = state.valueOrNull;
    if (s == null) return;

    final next = s.currentIndex + 1;

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

  /// Reset the queue and reload from the first page of the highest-priority spec.
  Future<void> refresh() async {
    _specIndex = 0;
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
