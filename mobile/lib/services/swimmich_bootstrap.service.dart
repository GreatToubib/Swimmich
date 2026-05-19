import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/album.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

/// The six "system" albums Swimmich manages on behalf of the user.
///
/// Names are user-visible and intentionally prefixed with `_` so they sort to
/// the top and look distinct from user-created albums. The storage key is the
/// flutter_secure_storage slot where the album's remote id is cached.
enum SwimmichSystemAlbum {
  newAssets._('_New', 'swimmich.album.new'),
  reviewLater._('_Review later', 'swimmich.album.review_later'),
  sorted._('_Sorted', 'swimmich.album.sorted'),
  oneStar._('_1 Star', 'swimmich.album.one_star'),
  twoStar._('_2 Star', 'swimmich.album.two_star'),
  threeStar._('_3 Star', 'swimmich.album.three_star');

  const SwimmichSystemAlbum._(this.albumName, this.storageKey);
  final String albumName;
  final String storageKey;
}

enum SystemAlbumIssueKind { missing, renamed, deleted }

class SystemAlbumIssue {
  const SystemAlbumIssue(this.album, this.kind, {this.cachedId});
  final SwimmichSystemAlbum album;
  final SystemAlbumIssueKind kind;
  final String? cachedId;
}

class SwimmichBootstrapException implements Exception {
  SwimmichBootstrapException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SwimmichBootstrapException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Outcome of [SwimmichBootstrapService.discoverSystemAlbums]: which albums
/// already exist and match the cache, plus a list of issues for the caller
/// (typically the UI layer) to confirm before recreating.
class SystemAlbumDiscovery {
  SystemAlbumDiscovery({required this.existing, required this.issues});

  /// Album → cached remote id, for albums whose cached id is still alive on
  /// the server with the expected name. Always partial — the missing entries
  /// are exactly the ones in [issues].
  final Map<SwimmichSystemAlbum, String> existing;

  /// Albums whose cache is missing, stale (renamed), or pointing at a deleted
  /// remote album. Recreating clears the issue.
  final List<SystemAlbumIssue> issues;
}

class SwimmichBootstrapService {
  SwimmichBootstrapService(this._albumApi, this._albumsApi, this._searchApi, this._storage);

  static const _backfillCompleteKey = 'swimmich.backfill.complete';
  static const _backfillCursorKey = 'swimmich.backfill.cursor_page';
  static const _backfillBatchSize = 250;

  final AlbumApiRepository _albumApi;
  final AlbumsApi _albumsApi;
  final SearchApi _searchApi;
  final SecureStorageRepository _storage;
  final _log = Logger('SwimmichBootstrapService');

  /// Inspect the cache and server for the six system albums. Returns which are
  /// already valid and which need (re)creating — the UI is expected to
  /// confirm before calling [resolveIssues].
  Future<SystemAlbumDiscovery> discoverSystemAlbums() async {
    final remote = await _albumApi.getAll(shared: null);
    final byId = <String, Album>{};
    final byName = <String, Album>{};
    for (final album in remote) {
      if (album.remoteId != null) byId[album.remoteId!] = album;
      byName[album.name] = album;
    }

    final existing = <SwimmichSystemAlbum, String>{};
    final issues = <SystemAlbumIssue>[];

    for (final album in SwimmichSystemAlbum.values) {
      final cachedId = await _storage.read(album.storageKey);

      if (cachedId != null) {
        final cached = byId[cachedId];
        if (cached == null) {
          // Cached id points at an album the server no longer has.
          issues.add(SystemAlbumIssue(album, SystemAlbumIssueKind.deleted, cachedId: cachedId));
          continue;
        }
        if (cached.name != album.albumName) {
          // The album our cache points at has been renamed by the user.
          issues.add(SystemAlbumIssue(album, SystemAlbumIssueKind.renamed, cachedId: cachedId));
          continue;
        }
        existing[album] = cachedId;
        continue;
      }

      // No cached id. If an album with the expected name happens to exist
      // (user already created one manually, or a reinstall), adopt it.
      final byNameMatch = byName[album.albumName];
      if (byNameMatch != null && byNameMatch.remoteId != null) {
        await _storage.write(album.storageKey, byNameMatch.remoteId!);
        existing[album] = byNameMatch.remoteId!;
        continue;
      }

      issues.add(SystemAlbumIssue(album, SystemAlbumIssueKind.missing));
    }

    return SystemAlbumDiscovery(existing: existing, issues: issues);
  }

  /// Create the albums flagged in [issues] (or replace the stale cache entry
  /// for `renamed`/`deleted` ones) and persist their ids.
  Future<Map<SwimmichSystemAlbum, String>> resolveIssues(
    SystemAlbumDiscovery discovery,
  ) async {
    final result = Map<SwimmichSystemAlbum, String>.from(discovery.existing);

    for (final issue in discovery.issues) {
      try {
        final created = await _albumApi.create(issue.album.albumName, assetIds: const []);
        final id = created.remoteId;
        if (id == null) {
          throw SwimmichBootstrapException(
            'Server returned an album without an id for ${issue.album.albumName}',
          );
        }
        await _storage.write(issue.album.storageKey, id);
        result[issue.album] = id;
        _log.info('Created system album ${issue.album.albumName} ($id, was ${issue.kind.name})');
      } catch (e, st) {
        _log.severe('Failed to create system album ${issue.album.albumName}', e, st);
        throw SwimmichBootstrapException(
          'Could not create ${issue.album.albumName}',
          e,
        );
      }
    }

    return result;
  }

  Future<bool> isBackfillComplete() async =>
      (await _storage.read(_backfillCompleteKey)) == '1';

  /// Reset the backfill state so [runBackfill] will start again from page 1.
  /// Intended for tests / "redo bootstrap" diagnostics.
  Future<void> resetBackfillState() async {
    await _storage.delete(_backfillCompleteKey);
    await _storage.delete(_backfillCursorKey);
  }

  /// Walk every server asset and add anything not already classified into the
  /// `_New` album. Idempotent (relies on the server's bulk-add returning
  /// `duplicate` for already-present assets) and resumable (persists the
  /// last-completed page).
  ///
  /// [onProgress] is invoked after each batch with `(processed, total)`.
  /// `total` may be 0 until the first response arrives.
  ///
  /// [shouldCancel], if provided, is polled before each network call; if it
  /// returns true the function returns early and the cursor is left intact so
  /// the next call resumes from the same page.
  Future<void> runBackfill(
    Map<SwimmichSystemAlbum, String> albums, {
    void Function(int processed, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    if (await isBackfillComplete()) return;

    final newAlbumId = albums[SwimmichSystemAlbum.newAssets];
    if (newAlbumId == null) {
      throw SwimmichBootstrapException('_New album id missing — bootstrap not finished');
    }

    // Build the "already managed" asset set: anything in _Sorted, _Review
    // later, or any of the star albums should not be force-added to _New.
    // We accept that this set is a snapshot — assets moved between albums
    // mid-backfill may briefly end up in _New as well, which is harmless
    // (they'll just appear there too).
    final managed = <String>{};
    for (final entry in albums.entries) {
      if (entry.key == SwimmichSystemAlbum.newAssets) continue;
      try {
        final dto = await _albumsApi.getAlbumInfo(entry.value);
        if (dto == null) continue;
        for (final asset in dto.assets) {
          managed.add(asset.id);
        }
      } catch (e, st) {
        _log.warning('Failed to enumerate album ${entry.key.albumName}', e, st);
        // Continue — worst case we add a couple of extra assets to _New.
      }
    }

    final cursorStr = await _storage.read(_backfillCursorKey);
    int page = int.tryParse(cursorStr ?? '') ?? 1;
    int processed = 0;
    int total = 0;

    while (true) {
      if (shouldCancel?.call() == true) {
        _log.info('Backfill cancelled at page $page');
        return;
      }

      final response = await _searchApi.searchAssets(
        MetadataSearchDto(
          page: page,
          size: _backfillBatchSize,
          withDeleted: false,
        ),
      );
      if (response == null) break;

      total = response.assets.total;

      final batchIds = <String>[];
      for (final asset in response.assets.items) {
        if (!managed.contains(asset.id)) batchIds.add(asset.id);
      }

      if (batchIds.isNotEmpty) {
        await _albumApi.addAssets(newAlbumId, batchIds);
      }

      processed += response.assets.items.length;
      onProgress?.call(processed, total);

      await _storage.write(_backfillCursorKey, page.toString());

      final next = response.assets.nextPage;
      if (next == null) break;
      page = int.tryParse(next) ?? (page + 1);
    }

    await _storage.write(_backfillCompleteKey, '1');
    await _storage.delete(_backfillCursorKey);
    _log.info('Backfill complete ($processed assets scanned, total reported: $total)');
  }
}

final swimmichBootstrapServiceProvider = Provider(
  (ref) => SwimmichBootstrapService(
    ref.watch(albumApiRepositoryProvider),
    ref.watch(apiServiceProvider).albumsApi,
    ref.watch(apiServiceProvider).searchApi,
    ref.watch(secureStorageRepositoryProvider),
  ),
);
