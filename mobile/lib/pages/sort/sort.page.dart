import 'dart:async' show unawaited;
import 'dart:ui' show lerpDouble;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/pages/sort/sort_source_sheet.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/local_delete_queue.provider.dart';
import 'package:immich_mobile/providers/sort_filter.provider.dart';
import 'package:immich_mobile/providers/sort_settings.provider.dart';
import 'package:immich_mobile/presentation/sort/quick_pick_row.dart';
import 'package:immich_mobile/presentation/sort/star_rating_bar.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/presentation/sort/storage_badge.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';
import 'package:immich_mobile/providers/sort_queue.provider.dart';
import 'package:immich_mobile/widgets/swimmich/undo_banner.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/providers/undo_stack.provider.dart';
import 'package:immich_mobile/services/sort_action.service.dart';
import 'package:immich_mobile/widgets/common/immich_app_bar.dart';
import 'package:openapi/api.dart';

AssetType _toAssetType(AssetTypeEnum t) => switch (t) {
      AssetTypeEnum.IMAGE => AssetType.image,
      AssetTypeEnum.VIDEO => AssetType.video,
      AssetTypeEnum.AUDIO => AssetType.audio,
      _ => AssetType.other,
    };

/// Refreshes the album cache (for chip labels) and prunes any pinned/recent
/// quick-pick chips whose album has been deleted on the server. Called on Sort
/// page mount and again every time the Sort tab is re-opened, since the tab is
/// kept alive and would otherwise never re-check.
Future<void> _refreshAlbumsAndPrune(WidgetRef ref) async {
  unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
  final albumApi = ref.read(albumApiRepositoryProvider);
  final quickPick = ref.read(quickPickProvider.notifier);
  try {
    final albums = await albumApi.getAll(shared: null);
    final ids = albums.map((a) => a.remoteId).whereType<String>().toSet();
    // Wait for the persisted pinned/recent state to load — on a cold start the
    // prune would otherwise run against the empty initial state and miss the
    // dead albums until the next tab switch.
    await quickPick.loaded;
    await quickPick.pruneDeleted(ids);
  } catch (_) {
    // Offline or transient failure — leave chips as-is.
  }
}

@RoutePage()
class SortPage extends HookConsumerWidget {
  const SortPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(sortQueueProvider);
    final notifier = ref.read(sortQueueProvider.notifier);

    // Pre-warm thumbnail cache whenever the current card changes.
    useEffect(
      () {
        final state = queueAsync.valueOrNull;
        if (state?.current != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => notifier.prefetchNext(context),
          );
        }
        return null;
      },
      [queueAsync.valueOrNull?.currentIndex],
    );

    // On first mount: load album names, prune deleted quick-pick chips, and
    // reload the deck from the server.
    useEffect(() {
      unawaited(_refreshAlbumsAndPrune(ref));
      unawaited(ref.read(sortQueueProvider.notifier).refresh());
      return null;
    }, const []);

    // The Sort tab is kept alive by AutoTabsRouter, so this page does not
    // remount when re-opened. Re-run the refresh+prune each time the Sort tab
    // becomes active, to catch albums deleted on the server in the meantime,
    // and reload the deck when the user is caught up (never mid-sort).
    ref.listen<TabEnum>(tabProvider, (prev, next) {
      if (next == TabEnum.sort && prev != TabEnum.sort) {
        unawaited(_refreshAlbumsAndPrune(ref));
        final q = ref.read(sortQueueProvider).valueOrNull;
        if (q == null || q.current == null) {
          unawaited(ref.read(sortQueueProvider.notifier).refresh());
        }
      }
      // Leaving the Sort tab: flush any queued local-copy deletions in one batch.
      if (prev == TabEnum.sort && next != TabEnum.sort) {
        unawaited(ref.read(localDeleteQueueProvider.notifier).flush());
      }
    });

    // Flush queued local deletions once the deck is fully drained.
    final caughtUp = queueAsync.valueOrNull != null &&
        queueAsync.valueOrNull!.current == null &&
        !queueAsync.valueOrNull!.hasMore;
    useEffect(() {
      if (caughtUp) {
        unawaited(ref.read(localDeleteQueueProvider.notifier).flush());
      }
      return null;
    }, [caughtUp]);

    return Scaffold(
      appBar: const ImmichAppBar(actions: [_SortFilterButton()]),
      backgroundColor: Colors.black,
      body: queueAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) =>
            _ErrorView(error: e.toString(), onRetry: notifier.refresh),
        data: (queue) => queue.current == null
            // A batch is still loading — keep the spinner so the lazy paging is
            // invisible; only show "all caught up" once truly exhausted.
            ? (queue.hasMore
                ? const _LoadingView()
                : _AllCaughtUpView(onRefresh: notifier.refresh))
            : Column(
                children: [
                  Expanded(
                    child: _SortDeckView(
                      asset: queue.current!,
                      remaining: queue.leftToSort,
                      nextAsset: queue.nextAsset,
                    ),
                  ),
                  const QuickPickRow(),
                ],
              ),
      ),
    );
  }
}

// ─── Loading ─────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

// ─── Error ───────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Could not load photos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _AllCaughtUpView extends StatelessWidget {
  const _AllCaughtUpView({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              'All caught up!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'No new photos to sort right now.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Swipe-deck card ──────────────────────────────────────────────────────────

class _SortDeckView extends ConsumerStatefulWidget {
  const _SortDeckView({
    required this.asset,
    required this.remaining,
    this.nextAsset,
  });

  final AssetResponseDto asset;
  final int remaining;
  final AssetResponseDto? nextAsset;

  @override
  ConsumerState<_SortDeckView> createState() => _SortDeckViewState();
}

class _SortDeckViewState extends ConsumerState<_SortDeckView>
    with TickerProviderStateMixin {
  /// Current drag offset while the user is touching the screen.
  Offset _drag = Offset.zero;

  /// True while a fly-off or bounce-back animation is playing.
  bool _isAnimating = false;

  /// Star rating selected by the user for the current card (0 = none, 1–5).
  int _starRating = 0;

  /// Whether the current card is marked favourite (heart toggle).
  bool _isFavorite = false;

  /// The device-asset id of this card's local copy, if it also exists on this
  /// phone (null = cloud-only). Drives the storage ✓ and the local-delete.
  String? _localId;

  /// Whether this card's local copy should be queued for deletion on swipe.
  /// Seeded from the [deleteLocalOnSortProvider] setting; user-overridable.
  bool _deleteLocalThisCard = false;

  /// The asset's state when the card opened (edit mode), used to compute what
  /// to revert on undo and which albums to remove when de-selected.
  Set<String> _originalUserAlbumIds = const {};
  int _originalStarRating = 0;
  bool _originalFavorite = false;
  SortStatus _originalSortStatus = SortStatus.new_;

  /// Prevents the haptic from firing on every frame at threshold.
  bool _hapticFired = false;

  /// Drives the card off-screen after a committed swipe.
  late final AnimationController _flyController;
  late Animation<Offset> _flyAnimation;

  /// Snaps the card back to centre after a rejected drag.
  late final AnimationController _bounceController;
  late Animation<Offset> _bounceAnimation;

  static const double _hThreshold = 90.0;
  static const double _vThreshold = 70.0;

  @override
  void initState() {
    super.initState();
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _resetAndPrefill();
  }

  @override
  void didUpdateWidget(covariant _SortDeckView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new card slid into place — reset the rating/selection and pre-fill from
    // the new asset's existing album & star membership.
    if (oldWidget.asset.id != widget.asset.id) {
      _resetAndPrefill();
    }
  }

  @override
  void dispose() {
    _flyController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  // ── Edit-mode pre-fill ───────────────────────────────────────────────────

  /// Clears the rating/selection then pre-fills them from the current asset's
  /// membership. Deferred to a microtask so provider writes happen outside the
  /// build phase.
  void _resetAndPrefill() {
    final asset = widget.asset;
    // Native fields are already on the asset DTO — seed the UI synchronously.
    final rating = asset.exifInfo?.rating?.toInt() ?? 0;
    _originalStarRating = rating;
    _originalFavorite = asset.isFavorite;
    _originalSortStatus = asset.sortStatus;
    _originalUserAlbumIds = const {};
    _localId = null;
    Future.microtask(() {
      if (!mounted || widget.asset.id != asset.id) return;
      setState(() {
        _starRating = rating;
        _isFavorite = asset.isFavorite;
        _deleteLocalThisCard = ref.read(deleteLocalOnSortProvider);
      });
      ref.read(quickPickProvider.notifier).clearSelection();
      unawaited(_prefillAlbums(asset.id));
      unawaited(_resolveLocalId(asset.id));
    });
  }

  /// Looks up whether this card's photo also exists locally on this device
  /// (matched by checksum in the Drift store) and records its device-asset id.
  Future<void> _resolveLocalId(String assetId) async {
    try {
      final remote =
          await ref.read(remoteAssetRepositoryProvider).get(assetId);
      if (!mounted || widget.asset.id != assetId) return;
      setState(() => _localId = remote?.localId);
    } catch (_) {
      // Best-effort; treat as cloud-only on failure.
    }
  }

  /// Looks up which user albums the asset is already in and pre-selects the
  /// matching quick-pick chips, so an already-curated card opens with its
  /// current album membership shown.
  Future<void> _prefillAlbums(String assetId) async {
    try {
      final albums = await ref
          .read(apiServiceProvider)
          .albumsApi
          .getAllAlbums(assetId: assetId);
      if (albums == null || !mounted || widget.asset.id != assetId) return;

      final memberIds = albums.map((a) => a.id).toSet();
      _originalUserAlbumIds = memberIds;
      ref.read(quickPickProvider.notifier).setSelection(memberIds);
    } catch (_) {
      // Membership lookup is best-effort; ignore failures.
    }
  }

  // ── Direction helpers ──────────────────────────────────────────────────────

  SortAction? get _activeAction {
    if (_drag.dy > _vThreshold && _drag.dy > _drag.dx.abs()) {
      return SortAction.reviewLater;
    }
    if (_drag.dx > _hThreshold) return SortAction.sorted;
    if (_drag.dx < -_hThreshold) return SortAction.delete;
    return null;
  }

  Color? get _overlayColor {
    final action = _activeAction;
    if (action != null) {
      return switch (action) {
        SortAction.delete => Colors.red,
        SortAction.sorted => Colors.green,
        SortAction.reviewLater => Colors.amber,
      };
    }
    if (_drag.dx < -20) return Colors.red;
    if (_drag.dx > 20) return Colors.green;
    if (_drag.dy > 20) return Colors.amber;
    return null;
  }

  double get _overlayOpacity => (_drag.distance / 140).clamp(0.0, 0.55);
  double get _rotation => _drag.dx / 700;

  IconData get _directionIcon => switch (_activeAction) {
        SortAction.delete => Icons.delete_rounded,
        SortAction.reviewLater => Icons.schedule_rounded,
        SortAction.sorted => Icons.check_circle_rounded,
        null => _drag.dx < 0
            ? Icons.delete_rounded
            : _drag.dx > 0
                ? Icons.check_circle_rounded
                : Icons.schedule_rounded,
      };

  String get _directionLabel => switch (_activeAction) {
        SortAction.delete => 'Delete',
        SortAction.reviewLater => 'Later',
        SortAction.sorted => 'Sort',
        null => '',
      };

  // ── Gesture callbacks ──────────────────────────────────────────────────────

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isAnimating) return;
    setState(() => _drag += d.delta);
    if (!_hapticFired && _activeAction != null) {
      ref.read(hapticFeedbackProvider.notifier).mediumImpact();
      _hapticFired = true;
    }
    if (_activeAction == null) _hapticFired = false;
  }

  void _onPanEnd(DragEndDetails _) {
    final action = _activeAction;
    if (action == null) {
      _bounceBack();
      return;
    }
    // Keeping is always allowed — rating, favourite and album are all optional.
    _commitAction(action);
  }

  // ── Animations ─────────────────────────────────────────────────────────────

  void _bounceBack() {
    _bounceAnimation = Tween<Offset>(begin: _drag, end: Offset.zero).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
    _isAnimating = true;
    _bounceController
      ..reset()
      ..forward().then((_) {
        if (mounted) {
          setState(() {
            _drag = Offset.zero;
            _isAnimating = false;
            _hapticFired = false;
          });
        }
      });
  }

  Future<void> _commitAction(SortAction action) async {
    final screenSize = MediaQuery.sizeOf(context);
    final target = switch (action) {
      SortAction.delete => Offset(-screenSize.width * 1.5, _drag.dy),
      SortAction.sorted => Offset(screenSize.width * 1.5, _drag.dy),
      SortAction.reviewLater => Offset(_drag.dx, screenSize.height * 1.5),
    };

    _flyAnimation = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _flyController, curve: Curves.easeIn),
    );
    _isAnimating = true;
    _flyController.reset();

    // 1. Play fly-off animation.
    await _flyController.forward();
    if (!mounted) return;

    // 2. Optimistically advance to the next card.
    await ref.read(sortQueueProvider.notifier).advance();
    if (!mounted) return;

    // Capture the swiped card's values before the deck advances.
    final assetId = widget.asset.id;
    final qpIds = ref.read(quickPickProvider).selected.toList();
    final starRating = _starRating;
    final favorite = _isFavorite;
    final previousQpIds = _originalUserAlbumIds.toList();
    final previousStar = _originalStarRating;
    final previousFavorite = _originalFavorite;
    final previousSortStatus = _originalSortStatus;
    // Queue the local copy for batched deletion if the card opted in.
    final localDeleteId =
        (_deleteLocalThisCard && _localId != null) ? _localId : null;

    // Reset drag state. The rating/selection for the next card are reset and
    // re-filled by didUpdateWidget → _resetAndPrefill once it slides in.
    setState(() {
      _drag = Offset.zero;
      _isAnimating = false;
      _hapticFired = false;
    });
    _flyController.reset();

    // 3. Push undo record; show SnackBar only for delete.
    final record = UndoRecord(
      asset: widget.asset,
      action: action,
      quickPickIds: qpIds,
      previousQuickPickIds: previousQpIds,
      starRating: starRating,
      previousStarRating: previousStar,
      favorite: favorite,
      previousFavorite: previousFavorite,
      previousSortStatus: previousSortStatus,
      localDeleteId: localDeleteId,
    );
    ref.read(undoStackProvider.notifier).push(record);

    // Queue the local-copy deletion (flushed in one batch on leaving the deck).
    if (localDeleteId != null) {
      ref.read(localDeleteQueueProvider.notifier).add(localDeleteId);
    }

    if (action == SortAction.delete && mounted) {
      showSwimmichUndoBanner(
        context,
        message: 'Photo deleted',
        onUndo: () => _executeUndo(record),
      );
    }

    // 4. Execute the API call (background; roll back on failure).
    try {
      await ref.read(sortActionServiceProvider).execute(
            assetId,
            action,
            quickPickAlbumIds: action == SortAction.sorted ? qpIds : const [],
            previousQuickPickAlbumIds:
                action == SortAction.sorted ? previousQpIds : const [],
            starRating: action == SortAction.sorted ? starRating : null,
            favorite: action == SortAction.sorted ? favorite : false,
          );
      if (action == SortAction.sorted && mounted) {
        ref.read(quickPickProvider.notifier).recordUsage(qpIds);
        // Selection is not cleared here — didUpdateWidget re-fills it for the
        // next card from that card's own membership.
      }
    } catch (e) {
      ref.read(sortQueueProvider.notifier).revertAdvance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
  }

  Future<void> _executeUndo(UndoRecord record) async {
    ref.read(undoStackProvider.notifier).pop();
    ref.read(sortQueueProvider.notifier).insertAtCurrent(record.asset);
    // Cancel any pending local-copy deletion for this card.
    if (record.localDeleteId != null) {
      ref.read(localDeleteQueueProvider.notifier).remove(record.localDeleteId!);
    }
    try {
      await ref.read(sortActionServiceProvider).undo(record);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Undo failed: $e')),
        );
      }
    }
  }

  // ── Peek card ──────────────────────────────────────────────────────────────

  Widget _buildPeekCard(AssetResponseDto asset, Size size) {
    final progress = (_drag.distance / 120).clamp(0.0, 1.0);
    final scale = lerpDouble(0.94, 1.0, progress)!;
    final yOffset = lerpDouble(14.0, 0.0, progress)!;
    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Transform.scale(
        scale: scale,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: RemoteImageProvider.thumbnail(
              assetId: asset.id,
              thumbhash: asset.thumbhash ?? '',
            ),
            fit: BoxFit.contain,
            width: size.width,
            height: size.height,
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    Widget mainCard = Stack(
      children: [
        // Solid background so portrait photos don't reveal the peek card.
        const Positioned.fill(child: ColoredBox(color: Colors.black)),

        // Photo — full preview quality with progressive loading.
        Positioned.fill(
          child: Image(
            image: RemoteFullImageProvider(
              assetId: widget.asset.id,
              thumbhash: widget.asset.thumbhash ?? '',
              assetType: _toAssetType(widget.asset.type),
              isAnimated: widget.asset.livePhotoVideoId != null,
            ),
            fit: BoxFit.contain,
          ),
        ),

        // Directional colour overlay.
        if (_overlayColor != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: _overlayColor!.withValues(alpha: _overlayOpacity),
              ),
            ),
          ),

        // Swipe action icon + label (fades in during drag).
        if (_drag.distance > 15)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: (_drag.distance / 100).clamp(0.0, 1.0),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_directionIcon, color: Colors.white, size: 80),
                      const SizedBox(height: 8),
                      Text(
                        _directionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Cloud/local badge — top left.
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 16,
          child: StorageBadge(asset: widget.asset, isLocal: _localId != null),
        ),

        // Remaining-count chip — top right.
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          right: 16,
          child: _CountChip(remaining: widget.remaining),
        ),

        // Local-delete toggle — top right, under the count chip. Only shown for
        // photos that also exist on this device; makes clear it's a LOCAL delete.
        if (_localId != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 52,
            right: 16,
            child: _LocalDeleteToggle(
              active: _deleteLocalThisCard,
              onChanged: (v) => setState(() => _deleteLocalThisCard = v),
            ),
          ),

        // Video indicator — centred play icon shown while the card is at rest.
        if (widget.asset.type == AssetTypeEnum.VIDEO && _drag.distance < 15)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white70,
                  size: 72,
                ),
              ),
            ),
          ),

        // Favourite heart — bottom left.
        Positioned(
          left: 12,
          bottom: 12,
          child: _FavoriteHeart(
            isFavorite: _isFavorite,
            onChanged: (v) => setState(() => _isFavorite = v),
          ),
        ),

        // Star rating bar — bottom right.
        Positioned(
          right: 12,
          bottom: 12,
          child: StarRatingBar(
            rating: _starRating,
            onChanged: (v) => setState(() => _starRating = v),
          ),
        ),
      ],
    );

    // Wrap main card with the appropriate transform.
    if (_isAnimating && _bounceController.isAnimating) {
      mainCard = AnimatedBuilder(
        animation: _bounceController,
        builder: (_, child) {
          final o = _bounceAnimation.value;
          return Transform.translate(
            offset: o,
            child: Transform.rotate(angle: o.dx / 700, child: child),
          );
        },
        child: mainCard,
      );
    } else if (_isAnimating && _flyController.isAnimating) {
      mainCard = AnimatedBuilder(
        animation: _flyController,
        builder: (_, child) {
          final o = _flyAnimation.value;
          return Transform.translate(
            offset: o,
            child: Transform.rotate(angle: o.dx / 700, child: child),
          );
        },
        child: mainCard,
      );
    } else if (!_isAnimating) {
      mainCard = Transform.translate(
        offset: _drag,
        child: Transform.rotate(angle: _rotation, child: mainCard),
      );
    }

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Stack(
        children: [
          // Peek card behind the main card — only shown while dragging.
          if (widget.nextAsset != null && (_drag != Offset.zero || _isAnimating))
            Positioned.fill(
              child: _buildPeekCard(widget.nextAsset!, size),
            ),
          // Main (draggable) card on top.
          Positioned.fill(child: mainCard),
        ],
      ),
    );
  }
}

// ─── Source filter button (app-bar header) ────────────────────────────────────

/// Header button that opens the two-section (status + album) source filter.
/// A badge shows how many filter options are currently selected.
class _SortFilterButton extends ConsumerWidget {
  const _SortFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(sortFilterProvider).selectionCount;
    return IconButton(
      tooltip: 'Filter photos to sort',
      onPressed: () => showSortSourceSheet(context, ref),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.filter_list),
      ),
    );
  }
}

// ─── Local-delete toggle ───────────────────────────────────────────────────────

/// Per-card toggle that marks the photo's LOCAL (phone) copy for deletion. The
/// phone glyph + tooltip make clear this removes the device copy only — the
/// cloud copy is untouched. Queued deletes are flushed in one batch on leaving.
class _LocalDeleteToggle extends StatelessWidget {
  const _LocalDeleteToggle({required this.active, required this.onChanged});

  final bool active;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active
          ? 'Will delete the copy on this phone (cloud copy kept)'
          : 'Keep the copy on this phone',
      triggerMode: TooltipTriggerMode.longPress,
      child: GestureDetector(
        onTap: () => onChanged(!active),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.red.withValues(alpha: 0.85) : Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.phonelink_erase
                    : Icons.phonelink_erase_outlined,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.smartphone, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Favourite heart toggle ───────────────────────────────────────────────────

class _FavoriteHeart extends StatelessWidget {
  const _FavoriteHeart({required this.isFavorite, required this.onChanged});

  final bool isFavorite;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isFavorite),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 26,
          color: isFavorite ? Colors.redAccent : Colors.white,
        ),
      ),
    );
  }
}

// ─── Remaining count chip ─────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  const _CountChip({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$remaining left',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
