import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
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

  int _page = 1;
  final _log = Logger('SortQueueNotifier');

  @override
  Future<SortQueueState> build() => _load([]);

  // ─── Private helpers ─────────────────────────────────────────────────────

  Future<String?> _newAlbumId() => ref
      .read(secureStorageRepositoryProvider)
      .read(SwimmichSystemAlbum.newAssets.storageKey);

  Future<SortQueueState> _load(List<AssetResponseDto> existing) async {
    final albumId = await _newAlbumId();
    if (albumId == null) {
      _log.warning('_New album id not found — bootstrap may not have run yet');
      return const SortQueueState(assets: [], hasMore: false);
    }

    try {
      final resp = await ref.read(apiServiceProvider).searchApi.searchAssets(
            MetadataSearchDto(
              albumIds: [albumId],
              page: _page,
              size: _pageSize,
              withDeleted: false,
            ),
          );
      if (resp == null) return SortQueueState(assets: existing, hasMore: false);
      final items = resp.assets.items;
      return SortQueueState(
        assets: [...existing, ...items],
        currentIndex: existing.isEmpty ? 0 : existing.length,
        hasMore: resp.assets.nextPage != null,
      );
    } catch (e, st) {
      _log.severe('Failed to load _New album assets', e, st);
      rethrow;
    }
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Move to the next card. Transparently loads more assets when the buffer
  /// drops below [_loadMoreThreshold].
  Future<void> advance() async {
    final s = state.valueOrNull;
    if (s == null) return;

    final next = s.currentIndex + 1;

    // Transparently load the next page when running low.
    if (s.hasMore && (s.assets.length - next) < _loadMoreThreshold) {
      _page++;
      final updated = await _load(s.assets);
      state = AsyncData(updated.copyWith(currentIndex: next));
      return;
    }

    state = AsyncData(s.copyWith(currentIndex: next));
  }

  /// Reset the queue and reload from page 1.
  Future<void> refresh() async {
    _page = 1;
    state = const AsyncLoading();
    state = AsyncData(await _load([]));
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
