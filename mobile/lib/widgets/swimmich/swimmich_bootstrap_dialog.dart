import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/swimmich_bootstrap.service.dart';
import 'package:logging/logging.dart';

final _log = Logger('SwimmichBootstrap');

/// End-to-end first-run bootstrap for Swimmich's system albums.
///
/// Fast path: if all six albums are cached and the backfill flag is set, this
/// returns almost immediately. Otherwise it confirms with the user, creates
/// any missing albums, and shows a progress dialog while the asset backfill
/// runs.
///
/// Safe to call on every app launch and after every successful login.
/// Errors are caught and surfaced as a SnackBar — the caller does not need a
/// try/catch and login navigation should not be blocked by a bootstrap fault.
Future<void> runSwimmichBootstrap(BuildContext context, WidgetRef ref) async {
  final service = ref.read(swimmichBootstrapServiceProvider);

  SystemAlbumDiscovery discovery;
  try {
    discovery = await service.discoverSystemAlbums();
  } catch (e, st) {
    _log.severe('discoverSystemAlbums failed', e, st);
    _showError(context, 'Could not check Swimmich albums on the server.');
    return;
  }

  if (discovery.issues.isNotEmpty) {
    if (!context.mounted) return;
    final confirmed = await _confirmRecreation(context, discovery.issues);
    if (confirmed != true) return;
  }

  Map<SwimmichSystemAlbum, String> albums;
  try {
    albums = await service.resolveIssues(discovery);
  } catch (e, st) {
    _log.severe('resolveIssues failed', e, st);
    if (context.mounted) {
      _showError(context, 'Could not create Swimmich system albums.');
    }
    return;
  }

  if (await service.isBackfillComplete()) return;
  if (!context.mounted) return;

  await _runBackfillWithDialog(context, service, albums);
}

Future<bool?> _confirmRecreation(
  BuildContext context,
  List<SystemAlbumIssue> issues,
) {
  String describe(SystemAlbumIssue issue) {
    final what = switch (issue.kind) {
      SystemAlbumIssueKind.missing => 'missing',
      SystemAlbumIssueKind.renamed => 'renamed',
      SystemAlbumIssueKind.deleted => 'deleted on the server',
    };
    return '• ${issue.album.albumName} — $what';
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Set up Swimmich albums'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Swimmich needs the following system albums. Recreate them now?',
          ),
          const SizedBox(height: 12),
          ...issues.map(describe).map((line) => Text(line)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

Future<void> _runBackfillWithDialog(
  BuildContext context,
  SwimmichBootstrapService service,
  Map<SwimmichSystemAlbum, String> albums,
) async {
  final progress = ValueNotifier<_BackfillProgress>(const _BackfillProgress(0, 0));
  bool cancelled = false;

  // Fire the backfill off in parallel with showing the dialog. The dialog
  // listens to `progress` and closes itself when the future completes.
  final backfill = service
      .runBackfill(
        albums,
        onProgress: (p, t) => progress.value = _BackfillProgress(p, t),
        shouldCancel: () => cancelled,
      )
      .then((_) => null, onError: (Object e, StackTrace st) {
        _log.severe('runBackfill failed', e, st);
        return e;
      });

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      // Auto-close once the future settles.
      backfill.whenComplete(() {
        if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
      });

      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Setting up Swimmich'),
          content: ValueListenableBuilder<_BackfillProgress>(
            valueListenable: progress,
            builder: (_, p, __) {
              final fraction = p.total == 0 ? null : (p.processed / p.total).clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sorting your existing photos into _New…'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: fraction),
                  const SizedBox(height: 8),
                  Text(
                    p.total == 0
                        ? 'Starting…'
                        : '${p.processed} / ${p.total}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
              },
              child: const Text('Continue in background'),
            ),
          ],
        ),
      );
    },
  );

  // Await the result so any post-backfill caller sees a settled state.
  await backfill;
}

void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

class _BackfillProgress {
  const _BackfillProgress(this.processed, this.total);
  final int processed;
  final int total;
}
