import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/album.entity.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/quick_pick.provider.dart';
import 'package:immich_mobile/providers/system_album_ids.provider.dart';
import 'package:immich_mobile/providers/sort_queue.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/services/sort_action.service.dart';

/// Opens the full-search album picker. The user can select multiple albums
/// without the sheet closing, then tap "Sort" to sort the current card into
/// all selected albums at once.
Future<void> showAlbumPickerSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: const _AlbumPickerSheet(),
    ),
  );
}

class _AlbumPickerSheet extends ConsumerStatefulWidget {
  const _AlbumPickerSheet();

  @override
  ConsumerState<_AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<_AlbumPickerSheet> {
  final _searchController = TextEditingController();
  final _newNameController = TextEditingController();
  Timer? _debounce;
  String _filter = '';
  bool _showCreateField = false;
  bool _isCreating = false;
  String? _createError;
  bool _isSorting = false;

  List<Album>? _allAlbums;
  Set<String> _systemAlbumIds = {};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _fetchAlbums();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchAlbums() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ref.read(albumApiRepositoryProvider).getAll(shared: null),
        ref.read(systemAlbumIdsProvider.future),
      ]);
      if (mounted) {
        setState(() {
          _allAlbums = results[0] as List<Album>;
          _systemAlbumIds = results[1] as Set<String>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Album> get _filtered {
    final all = _allAlbums ?? [];
    return all
        .where((a) =>
            a.remoteId != null &&
            !a.name.startsWith('_') &&
            !_systemAlbumIds.contains(a.remoteId))
        .where((a) => a.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => setState(() => _filter = v),
    );
  }

  Future<void> _createAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final all = _allAlbums ?? [];
    if (all.any((a) => a.name == trimmed)) {
      setState(() => _createError = 'Album "$trimmed" already exists');
      return;
    }

    setState(() {
      _isCreating = true;
      _createError = null;
    });

    try {
      final album = await ref
          .read(albumApiRepositoryProvider)
          .create(trimmed, assetIds: const []);
      final remoteId = album.remoteId;
      if (remoteId != null) {
        ref.read(quickPickProvider.notifier).toggle(remoteId);
      }
      await _fetchAlbums();
      unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
      setState(() {
        _isCreating = false;
        _showCreateField = false;
        _newNameController.clear();
      });
    } catch (e) {
      setState(() {
        _isCreating = false;
        _createError = e.toString();
      });
    }
  }

  Future<void> _executeSortAndClose() async {
    final current = ref.read(sortQueueProvider).valueOrNull?.current;
    if (current == null) return;

    setState(() => _isSorting = true);
    final assetId = current.id;
    final qpIds = ref.read(quickPickProvider).selected.toList();

    try {
      await ref.read(sortQueueProvider.notifier).advance();
      await ref.read(sortActionServiceProvider).execute(
            assetId,
            SortAction.sorted,
            quickPickAlbumIds: qpIds,
          );
      ref.read(quickPickProvider.notifier).recordUsage(qpIds);
      ref.read(quickPickProvider.notifier).clearSelection();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isSorting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sort failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qp = ref.watch(quickPickProvider);
    final selectedCount = qp.selected.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
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
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Select album(s)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search albums…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // "New album" create row
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: _showCreateField
                ? TextField(
                    controller: _newNameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Album name',
                      errorText: _createError,
                      isDense: true,
                    ),
                    onSubmitted: _createAlbum,
                  )
                : const Text('New album'),
            trailing: _showCreateField
                ? _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () =>
                            _createAlbum(_newNameController.text),
                        child: const Text('Create'),
                      )
                : null,
            onTap: _showCreateField
                ? null
                : () => setState(() => _showCreateField = true),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Failed to load albums',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _fetchAlbums,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final album = _filtered[i];
                          final albumId = album.remoteId!;
                          final isSelected = qp.selected.contains(albumId);
                          return ListTile(
                            leading: Icon(
                              Icons.photo_album_outlined,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(album.name),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )
                                : null,
                            // Toggle selection — do NOT close the sheet.
                            onTap: () => ref
                                .read(quickPickProvider.notifier)
                                .toggle(albumId),
                          );
                        },
                      ),
          ),
          // Sort button — executes SortAction.sorted for the current card.
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 8,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: selectedCount == 0 || _isSorting
                    ? null
                    : _executeSortAndClose,
                icon: _isSorting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  selectedCount == 0
                      ? 'Select an album first'
                      : 'Sort into $selectedCount album${selectedCount == 1 ? '' : 's'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
