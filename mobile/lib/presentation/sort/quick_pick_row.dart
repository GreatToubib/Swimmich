import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/pages/sort/album_picker_sheet.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';

/// A horizontal row of 6 album chips displayed below the sort card.
///
/// Slots 0-2 are user-pinned (persist across sessions).
/// Slots 3-5 are MRU (30-day sliding window, auto-populated after sort).
/// Tapping a chip toggles it into the current selection; selected chips are
/// used by the right-swipe action.
class QuickPickRow extends ConsumerWidget {
  const QuickPickRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qp = ref.watch(quickPickProvider);
    final albumState = ref.watch(remoteAlbumProvider);
    final albums = albumState.albums;
    final chips = qp.chips;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: chips.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == chips.length) {
              return _MoreChip(
                onTap: () => showAlbumPickerSheet(context, ref),
              );
            }
            final chip = chips[i];
            final isPinnedSlot = i < 3;
            if (chip == null) {
              return _EmptySlot(
                slot: i,
                isPinnedSlot: isPinnedSlot,
                onTap: () => _showAlbumPicker(
                  context,
                  ref,
                  slot: i,
                  albums: albums,
                  qp: qp,
                ),
              );
            }
            final albumName = albums
                    .where((a) => a.id == chip.albumId)
                    .firstOrNull
                    ?.name ??
                '…';
            return _AlbumChip(
              albumName: albumName,
              isPinned: chip.isPinned,
              isSelected: qp.selected.contains(chip.albumId),
              onTap: () =>
                  ref.read(quickPickProvider.notifier).toggle(chip.albumId),
              onLongPress: chip.isPinned
                  ? () => _showAlbumPicker(
                        context,
                        ref,
                        slot: i,
                        albums: albums,
                        qp: qp,
                      )
                  : null,
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAlbumPicker(
    BuildContext context,
    WidgetRef ref, {
    required int slot,
    required List<RemoteAlbum> albums,
    required QuickPickState qp,
  }) async {
    if (albums.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AlbumPickerSheet(
        albums: albums,
        currentId: slot < 3 ? qp.pinned[slot] : null,
      ),
    );
    if (selected != null) {
      await ref.read(quickPickProvider.notifier).setPinned(slot, selected);
    }
  }
}

// ─── More chip ───────────────────────────────────────────────────────────────

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              'More',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty slot chip ─────────────────────────────────────────────────────────

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.slot,
    required this.isPinnedSlot,
    required this.onTap,
  });

  final int slot;
  final bool isPinnedSlot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: isPinnedSlot ? onTap : null,
      child: DottedBorderChip(
        label: isPinnedSlot ? 'Pin ${slot + 1}' : '',
        theme: theme,
      ),
    );
  }
}

class DottedBorderChip extends StatelessWidget {
  const DottedBorderChip({super.key, required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add,
            size: 14,
            color: theme.colorScheme.outline,
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Filled album chip ────────────────────────────────────────────────────────

class _AlbumChip extends StatelessWidget {
  const _AlbumChip({
    required this.albumName,
    required this.isPinned,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final String albumName;
  final bool isPinned;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          border: Border.all(
            color: isSelected ? primary : theme.colorScheme.outline,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPinned)
              Icon(
                Icons.push_pin,
                size: 12,
                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.outline,
              ),
            if (isPinned) const SizedBox(width: 4),
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Album picker sheet ───────────────────────────────────────────────────────

class _AlbumPickerSheet extends StatelessWidget {
  const _AlbumPickerSheet({
    required this.albums,
    required this.currentId,
  });

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
              'Pick an album',
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
                  title: Text(
                    album.name,
                    style: isCurrent
                        ? TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  trailing: isCurrent
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
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
