import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/sort_source_filter.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';

/// Opens the source-album selection sheet. Photos from every selected album
/// are merged (union) into the sort deck. New + Review Later are selected by
/// default; the picker prevents deselecting the last remaining album.
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

/// One selectable row: an album id with a display name.
typedef _SourceAlbum = ({String id, String name});

const _systemKindOrder = [
  'new',
  'review_later',
  'one_star',
  'two_star',
  'three_star',
];

class _SortSourceSheet extends ConsumerStatefulWidget {
  const _SortSourceSheet();

  @override
  ConsumerState<_SortSourceSheet> createState() => _SortSourceSheetState();
}

class _SortSourceSheetState extends ConsumerState<_SortSourceSheet> {
  List<_SourceAlbum> _system = const [];
  List<_SourceAlbum> _user = const [];
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
      final allAlbums =
          await ref.read(apiServiceProvider).albumsApi.getAllAlbums() ?? [];

      // System albums in canonical kind order.
      final byKind = {
        for (final a in allAlbums.where((a) => a.systemKind != null))
          a.systemKind!: (id: a.id, name: a.albumName),
      };
      final system = <_SourceAlbum>[
        for (final kind in _systemKindOrder)
          if (byKind.containsKey(kind)) byKind[kind]!,
      ];
      final systemIds = system.map((e) => e.id).toSet();

      // User albums (everything that isn't a system album), sorted by name.
      final all =
          await ref.read(albumApiRepositoryProvider).getAll(shared: null);
      final user = all
          .where((a) => a.remoteId != null && !systemIds.contains(a.remoteId))
          .map<_SourceAlbum>((a) => (id: a.remoteId!, name: a.name))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _system = system;
          _user = user;
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
    final selected = ref.watch(sortSourceAlbumsProvider);

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
                Text(
                  'Albums to sort',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${selected.length} selected',
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
          Expanded(child: _body(controller, selected)),
        ],
      ),
    );
  }

  Widget _body(ScrollController controller, Set<String> selected) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load albums',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      controller: controller,
      children: [
        if (_system.isNotEmpty) ...[
          const _SectionHeader('System'),
          for (final a in _system)
            _SourceTile(
              album: a,
              selected: selected.contains(a.id),
              onChanged: () =>
                  ref.read(sortSourceAlbumsProvider.notifier).toggle(a.id),
            ),
        ],
        if (_user.isNotEmpty) ...[
          const _SectionHeader('Albums'),
          for (final a in _user)
            _SourceTile(
              album: a,
              selected: selected.contains(a.id),
              onChanged: () =>
                  ref.read(sortSourceAlbumsProvider.notifier).toggle(a.id),
            ),
        ],
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
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.album,
    required this.selected,
    required this.onChanged,
  });

  final _SourceAlbum album;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => onChanged(),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(album.name),
    );
  }
}
