import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';

/// Settings widget for configuring the 3 pinned quick-pick album slots.
class SortSettings extends ConsumerWidget {
  const SortSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qp = ref.watch(quickPickProvider);
    final albumState = ref.watch(remoteAlbumProvider);
    final albums = albumState.albums;

    Widget pinnedTile(int slot) {
      final albumId = qp.pinned[slot];
      final albumName = albumId != null
          ? albums.where((a) => a.id == albumId).firstOrNull?.name ?? albumId
          : null;

      return ListTile(
        leading: Icon(
          Icons.push_pin_outlined,
          color: albumName != null ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text('Pinned album ${slot + 1}'),
        subtitle: Text(albumName ?? 'Not set'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (albumId != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear',
                onPressed: () =>
                    ref.read(quickPickProvider.notifier).setPinned(slot, null),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _showAlbumPicker(context, ref, slot, albums, qp),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Pinned albums appear as the first 3 chips while sorting. '
            'Slots 4-6 auto-fill from your most recently used albums.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ),
        pinnedTile(0),
        pinnedTile(1),
        pinnedTile(2),
      ],
    );
  }

  Future<void> _showAlbumPicker(
    BuildContext context,
    WidgetRef ref,
    int slot,
    List<RemoteAlbum> albums,
    QuickPickState qp,
  ) async {
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No albums found. Refresh the Albums tab first.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AlbumPickerSheet(
        albums: albums,
        currentId: qp.pinned[slot],
      ),
    );
    if (selected != null) {
      await ref.read(quickPickProvider.notifier).setPinned(slot, selected);
    }
  }
}

class _AlbumPickerSheet extends StatelessWidget {
  const _AlbumPickerSheet({required this.albums, required this.currentId});

  final List<RemoteAlbum> albums;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Select album',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: albums.length,
              itemBuilder: (_, i) {
                final album = albums[i];
                final isCurrent = album.id == currentId;
                return ListTile(
                  leading: Icon(
                    Icons.photo_album_outlined,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(album.name),
                  trailing: isCurrent
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(album.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
