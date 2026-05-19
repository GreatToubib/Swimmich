import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/providers/sort_queue.provider.dart';
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

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        // CustomScrollView satisfies RefreshIndicator's Scrollable requirement.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: queueAsync.when(
              loading: () => const _LoadingView(),
              error: (e, _) => _ErrorView(error: e.toString(), onRetry: notifier.refresh),
              data: (queue) => queue.current == null
                  ? _AllCaughtUpView(onRefresh: notifier.refresh)
                  : _SortCardView(
                      asset: queue.current!,
                      remaining: queue.remaining,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading ────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ─── Error ──────────────────────────────────────────────────────────────────

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

// ─── Empty state ────────────────────────────────────────────────────────────

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
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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

// ─── Card ────────────────────────────────────────────────────────────────────

class _SortCardView extends StatelessWidget {
  const _SortCardView({required this.asset, required this.remaining});

  final AssetResponseDto asset;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Photo ──────────────────────────────────────────────────────
          Positioned.fill(
            child: ImmichThumbnail(
              asset: Asset.remote(asset),
              width: size.width,
              height: size.height,
              fit: BoxFit.contain,
            ),
          ),

          // ── Remaining count chip ────────────────────────────────────
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 16,
            child: _CountChip(remaining: remaining),
          ),

          // ── Swipe-direction hints (gesture handling comes in S1.3) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: _SwipeHints(theme: theme),
          ),
        ],
      ),
    );
  }
}

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

class _SwipeHints extends StatelessWidget {
  const _SwipeHints({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _HintButton(
          icon: Icons.chevron_left,
          label: 'Skip',
          color: Colors.grey.shade300,
        ),
        _HintButton(
          icon: Icons.arrow_downward,
          label: 'Review\nlater',
          color: Colors.amber.shade300,
        ),
        _HintButton(
          icon: Icons.chevron_right,
          label: 'Sorted',
          color: Colors.green.shade300,
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
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black45,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
