import 'dart:async' show unawaited;
import 'dart:ui' show lerpDouble;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/pages/sort/sort_source_sheet.dart';
import 'package:immich_mobile/presentation/sort/quick_pick_row.dart';
import 'package:immich_mobile/presentation/sort/star_rating_bar.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/presentation/sort/storage_badge.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';
import 'package:immich_mobile/providers/sort_queue.provider.dart';
import 'package:immich_mobile/providers/sort_source_filter.provider.dart';
import 'package:immich_mobile/providers/system_album_ids.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:immich_mobile/providers/undo_stack.provider.dart';
import 'package:immich_mobile/services/sort_action.service.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';
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

    // On first mount: load album names and prune deleted quick-pick chips.
    useEffect(() {
      unawaited(_refreshAlbumsAndPrune(ref));
      return null;
    }, const []);

    // The Sort tab is kept alive by AutoTabsRouter, so this page does not
    // remount when re-opened. Re-run the refresh+prune each time the Sort tab
    // becomes active, to catch albums deleted on the server in the meantime.
    ref.listen<TabEnum>(tabProvider, (prev, next) {
      if (next == TabEnum.sort && prev != TabEnum.sort) {
        unawaited(_refreshAlbumsAndPrune(ref));
      }
    });

    return Scaffold(
      appBar: const ImmichAppBar(
        showUploadButton: false,
        actions: [_SourceButton()],
      ),
      backgroundColor: Colors.black,
      body: queueAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) =>
            _ErrorView(error: e.toString(), onRetry: notifier.refresh),
        data: (queue) => queue.current == null
            ? _AllCaughtUpView(
                onRefresh: () async {
                  await ref
                      .read(swimmichBootstrapServiceProvider)
                      .checkForNewAssets();
                  await notifier.refresh();
                },
              )
            : Column(
                children: [
                  Expanded(
                    child: _SortDeckView(
                      asset: queue.current!,
                      remaining: queue.remaining,
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

  /// Star rating selected by the user for the current card (0 = none, 1–3).
  int _starRating = 0;

  /// The asset's membership when the card opened (edit mode), used to compute
  /// what to remove when the user de-selects albums / changes the rating.
  Set<String> _originalUserAlbumIds = const {};
  int _originalStarRating = 0;
  bool _wasInNew = false;

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
    final assetId = widget.asset.id;
    _originalUserAlbumIds = const {};
    _originalStarRating = 0;
    _wasInNew = false;
    Future.microtask(() async {
      if (!mounted) return;
      setState(() => _starRating = 0);
      ref.read(quickPickProvider.notifier).clearSelection();
      await _prefillFromMembership(assetId);
    });
  }

  /// Looks up which albums the asset is already in and pre-selects the matching
  /// quick-pick albums and star rating, so an already-sorted card opens with
  /// its current state shown.
  Future<void> _prefillFromMembership(String assetId) async {
    try {
      final albums = await ref
          .read(apiServiceProvider)
          .albumsApi
          .getAllAlbums(assetId: assetId);
      if (albums == null || !mounted) return;
      // Guard against the card having advanced while we were fetching.
      if (widget.asset.id != assetId) return;

      final memberIds = albums.map((a) => a.id).toSet();
      final storage = ref.read(secureStorageRepositoryProvider);
      final oneId = await storage.read(SwimmichSystemAlbum.oneStar.storageKey);
      final twoId = await storage.read(SwimmichSystemAlbum.twoStar.storageKey);
      final threeId =
          await storage.read(SwimmichSystemAlbum.threeStar.storageKey);
      final newId =
          await storage.read(SwimmichSystemAlbum.newAssets.storageKey);

      int rating = 0;
      if (threeId != null && memberIds.contains(threeId)) {
        rating = 3;
      } else if (twoId != null && memberIds.contains(twoId)) {
        rating = 2;
      } else if (oneId != null && memberIds.contains(oneId)) {
        rating = 1;
      }

      // Pre-select only non-system albums as quick-pick chips.
      final systemIds = await ref.read(systemAlbumIdsProvider.future);
      final userMembers =
          memberIds.where((id) => !systemIds.contains(id)).toSet();

      if (!mounted || widget.asset.id != assetId) return;
      // Remember the opening state so a sort can reconcile (remove de-selected
      // albums / clear an old star rating).
      _originalUserAlbumIds = userMembers;
      _originalStarRating = rating;
      _wasInNew = newId != null && memberIds.contains(newId);
      ref.read(quickPickProvider.notifier).setSelection(userMembers);
      setState(() => _starRating = rating);
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
    if (action == SortAction.sorted &&
        ref.read(quickPickProvider).selected.isEmpty &&
        _starRating == 0) {
      _bounceBack();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select an album or star rating first'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
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
    final previousQpIds = _originalUserAlbumIds.toList();
    final previousStar = _originalStarRating;
    final wasInNew = _wasInNew;

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
      wasInNew: wasInNew,
    );
    ref.read(undoStackProvider.notifier).push(record);

    if (action == SortAction.delete && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Photo deleted'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 160, left: 16, right: 16),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _executeUndo(record),
          ),
        ),
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
          child: StorageBadge(asset: widget.asset),
        ),

        // Remaining-count chip — top right.
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          right: 16,
          child: _CountChip(remaining: widget.remaining),
        ),

        // Star rating bar — bottom right.
        // EDIT MODE: in a future edit-mode flow, pre-populate _starRating from
        // the asset's existing star album membership before displaying this card.
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

// ─── Source button (app-bar header) ──────────────────────────────────────────

/// Compact icon button shown in the Sort page header, between the Immich logo
/// and the profile button. Opens the source-album selection sheet; a small
/// badge shows how many source albums are currently selected.
class _SourceButton extends ConsumerWidget {
  const _SourceButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(sortSourceAlbumsProvider).length;
    return IconButton(
      tooltip: 'Albums to sort',
      onPressed: () => showSortSourceSheet(context, ref),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.filter_list),
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
