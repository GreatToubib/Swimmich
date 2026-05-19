import 'dart:ui' show lerpDouble;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/presentation/sort/quick_pick_row.dart';
import 'package:immich_mobile/presentation/sort/storage_badge.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';
import 'package:immich_mobile/providers/sort_queue.provider.dart';
import 'package:immich_mobile/providers/undo_stack.provider.dart';
import 'package:immich_mobile/services/sort_action.service.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';
import 'package:immich_mobile/widgets/common/immich_thumbnail.dart';
import 'package:openapi/api.dart';

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

    return queueAsync.when(
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
    );
  }
}

// ─── Loading ─────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ─── Error ───────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Could not load photos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: Theme.of(context).textTheme.bodySmall,
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
    return Scaffold(
      body: Center(
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
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'No new photos to sort right now.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
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
  }

  @override
  void dispose() {
    _flyController.dispose();
    _bounceController.dispose();
    super.dispose();
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
        ref.read(quickPickProvider).selected.isEmpty) {
      _bounceBack();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select an album chip below first'),
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

    // Reset visual state for the next card before the API call.
    setState(() {
      _drag = Offset.zero;
      _isAnimating = false;
      _hapticFired = false;
    });
    _flyController.reset();

    // 3. Push undo record and show SnackBar.
    final assetId = widget.asset.id;
    final qpIds = ref.read(quickPickProvider).selected.toList();
    final record =
        UndoRecord(asset: widget.asset, action: action, quickPickIds: qpIds);
    ref.read(undoStackProvider.notifier).push(record);

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_undoLabel(action)),
          duration: const Duration(seconds: 5),
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
            quickPickAlbumIds:
                action == SortAction.sorted ? qpIds : const [],
          );
      if (action == SortAction.sorted && mounted) {
        ref.read(quickPickProvider.notifier).recordUsage(qpIds);
        ref.read(quickPickProvider.notifier).clearSelection();
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

  String _undoLabel(SortAction action) => switch (action) {
        SortAction.delete => 'Photo deleted',
        SortAction.reviewLater => 'Saved for later',
        SortAction.sorted => 'Photo sorted',
      };

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
          child: ImmichThumbnail(
            asset: Asset.remote(asset),
            width: size.width,
            height: size.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final activeAction = _activeAction;

    Widget mainCard = Stack(
      children: [
        // Photo.
        Positioned.fill(
          child: ImmichThumbnail(
            asset: Asset.remote(widget.asset),
            width: size.width,
            height: size.height,
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

        // Swipe-hint buttons.
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          child: _SwipeHintBar(activeAction: activeAction),
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // Peek card behind the main card.
            if (widget.nextAsset != null)
              Positioned.fill(
                child: _buildPeekCard(widget.nextAsset!, size),
              ),
            // Main (draggable) card on top.
            Positioned.fill(child: mainCard),
          ],
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

// ─── Swipe-hint bar ───────────────────────────────────────────────────────────

class _SwipeHintBar extends StatelessWidget {
  const _SwipeHintBar({required this.activeAction});

  final SortAction? activeAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _HintButton(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: Colors.red.shade300,
          isActive: activeAction == SortAction.delete,
        ),
        _HintButton(
          icon: Icons.schedule_outlined,
          label: 'Later',
          color: Colors.amber.shade300,
          isActive: activeAction == SortAction.reviewLater,
        ),
        _HintButton(
          icon: Icons.check_circle_outline,
          label: 'Sorted',
          color: Colors.green.shade300,
          isActive: activeAction == SortAction.sorted,
        ),
      ],
    );
  }
}

class _HintButton extends StatelessWidget {
  const _HintButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isActive ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? color.withValues(alpha: 0.25)
                  : Colors.black45,
              border: Border.all(
                color: color,
                width: isActive ? 2.5 : 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
