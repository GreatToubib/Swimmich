import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/pages/sort/album_picker_sheet.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';

/// Two-row album chip section below the sort card.
///
/// Row 1 (PINNED): 3 user-pinned slots — long-press to reassign, tap to toggle.
/// Row 2 (RECENT): up to 3 auto-populated MRU albums — tap to toggle for sort.
/// "More" button at the end of the RECENT header opens the full album picker.
class QuickPickRow extends ConsumerWidget {
  const QuickPickRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qp = ref.watch(quickPickProvider);
    final albumState = ref.watch(remoteAlbumProvider);
    final albums = albumState.albums;
    final chips = qp.chips;

    String nameFor(String albumId) =>
        albums.where((a) => a.id == albumId).firstOrNull?.name ?? '…';

    Widget pinnedChip(int slot) {
      final chip = chips[slot];
      if (chip == null) {
        return _EmptySlot(
          slot: slot,
          isPinnedSlot: true,
          onTap: () => _showPinPicker(context, ref, slot: slot, albums: albums, qp: qp),
        );
      }
      return _AlbumChip(
        albumName: nameFor(chip.albumId),
        isSelected: qp.selected.contains(chip.albumId),
        onTap: () => ref.read(quickPickProvider.notifier).toggle(chip.albumId),
        onLongPress: () =>
            _showPinPicker(context, ref, slot: slot, albums: albums, qp: qp),
      );
    }

    Widget mruChip(int slot) {
      final chip = chips[slot];
      if (chip == null) return const SizedBox.shrink();
      return _AlbumChip(
        albumName: nameFor(chip.albumId),
        isSelected: qp.selected.contains(chip.albumId),
        onTap: () => ref.read(quickPickProvider.notifier).toggle(chip.albumId),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pinned row ─────────────────────────────────────────────────
            const _SectionLabel('PINNED'),
            const SizedBox(height: 4),
            Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  Expanded(child: pinnedChip(i)),
                  if (i < 2) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // ── Recent row ─────────────────────────────────────────────────
            Row(
              children: [
                const _SectionLabel('RECENT'),
                const Spacer(),
                _MoreChip(
                  onTap: () => showAlbumPickerSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  Expanded(child: mruChip(i + 3)),
                  if (i < 2) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPinPicker(
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
      builder: (_) => _PinPickerSheet(
        albums: albums,
        currentId: slot < 3 ? qp.pinned[slot] : null,
      ),
    );
    if (selected != null) {
      await ref.read(quickPickProvider.notifier).setPinned(slot, selected);
    }
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.45),
            letterSpacing: 0.8,
          ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: theme.colorScheme.outline),
            const SizedBox(width: 3),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.push_pin_outlined,
              size: 12,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 3),
            Text(
              'Pin ${slot + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filled album chip ────────────────────────────────────────────────────────

class _AlbumChip extends StatelessWidget {
  const _AlbumChip({
    required this.albumName,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final String albumName;
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                albumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pin-assignment picker sheet ──────────────────────────────────────────────
// Used only when the user long-presses a pinned slot to reassign it.

class _PinPickerSheet extends StatelessWidget {
  const _PinPickerSheet({
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

// Re-exported for backward compat (used by sort.page.dart indirectly).
// ignore: unused_element
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
          Icon(Icons.add, size: 14, color: theme.colorScheme.outline),
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
