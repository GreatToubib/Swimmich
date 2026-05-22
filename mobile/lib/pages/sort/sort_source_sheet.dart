import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/sort_filter.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:openapi/api.dart';

/// Opens the sort-source filter sheet. The deck shows photos whose triage
/// status is in the selected STATUSES section AND whose album membership
/// matches the selected ALBUMS section ("No album" or any selected album).
Future<void> showSortSourceSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: const _SortSourceSheet(),
    ),
  );
}

const _statusLabels = <SortStatus, String>{
  SortStatus.new_: 'New',
  SortStatus.reviewLater: 'Review later',
  SortStatus.kept: 'Kept',
};

typedef _UserAlbum = ({String id, String name});

class _SortSourceSheet extends ConsumerStatefulWidget {
  const _SortSourceSheet();

  @override
  ConsumerState<_SortSourceSheet> createState() => _SortSourceSheetState();
}

class _SortSourceSheetState extends ConsumerState<_SortSourceSheet> {
  List<_UserAlbum> _albums = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await ref.read(albumApiRepositoryProvider).getAll(shared: null);
      final albums = all
          .where((a) => a.remoteId != null)
          .map<_UserAlbum>((a) => (id: a.remoteId!, name: a.name))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _albums = albums;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(sortFilterProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Text('Filter photos to sort',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${filter.selectionCount} selected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(controller, filter)),
        ],
      ),
    );
  }

  Widget _body(ScrollController controller, SortFilterState filter) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load albums'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final notifier = ref.read(sortFilterProvider.notifier);

    return ListView(
      controller: controller,
      children: [
        const _SectionHeader('STATUS'),
        for (final entry in _statusLabels.entries)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(entry.value),
            value: filter.statuses.contains(entry.key),
            onChanged: (_) => notifier.toggleStatus(entry.key),
          ),
        const _SectionHeader('ALBUMS'),
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('No album'),
          value: filter.noAlbum,
          onChanged: (_) => notifier.toggleNoAlbum(),
        ),
        for (final album in _albums)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(album.name),
            value: filter.albumIds.contains(album.id),
            onChanged: (_) => notifier.toggleAlbum(album.id),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
