import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/album_api.repository.dart';
import 'package:immich_mobile/repositories/secure_storage.repository.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

/// The five "system" albums Swimmich manages on behalf of the user.
///
/// Identity is the [kind] string stored as `systemKind` on the server.
/// The [albumName] is the canonical English display name used when the server
/// provisions a new album; users may rename the album freely.
enum SwimmichSystemAlbum {
  newAssets._('_New', 'new'),
  reviewLater._('_Review Later', 'review_later'),
  oneStar._('⭐', 'one_star'),
  twoStar._('⭐⭐', 'two_star'),
  threeStar._('⭐⭐⭐', 'three_star');

  const SwimmichSystemAlbum._(this.albumName, this.kind);
  final String albumName;
  final String kind;
}

class SwimmichBootstrapService {
  SwimmichBootstrapService(
      this._albumApi, this._albumsApi, this._searchApi, this._storage);

  static const _kLastSeenAtKey = 'swimmich.last_seen_at';

  final AlbumApiRepository _albumApi;
  final AlbumsApi _albumsApi;
  final SearchApi _searchApi;
  final SecureStorageRepository _storage;
  final _log = Logger('SwimmichBootstrapService');

  /// Builds the set of asset IDs already in any system album except _New,
  /// identified by their [systemKind]. Used to avoid re-adding sorted/reviewed
  /// assets back into _New.
  Future<Set<String>> _buildManagedSet(
      List<AlbumResponseDto> systemAlbums) async {
    final managed = <String>{};
    for (final album in systemAlbums) {
      if (album.systemKind == 'new') continue;
      try {
        final dto = await _albumsApi.getAlbumInfo(album.id);
        if (dto == null) continue;
        for (final asset in dto.assets) {
          managed.add(asset.id);
        }
      } catch (e, st) {
        _log.warning('Failed to enumerate album ${album.albumName}', e, st);
      }
    }
    return managed;
  }

  /// Incremental check: finds assets created after the last known timestamp
  /// that are not already in a system album, and adds them to _New.
  Future<void> checkForNewAssets() async {
    final allAlbums = await _albumsApi.getAllAlbums();
    if (allAlbums == null) return;

    final systemAlbums =
        allAlbums.where((a) => a.systemKind != null).toList();
    final newAlbum =
        systemAlbums.where((a) => a.systemKind == 'new').firstOrNull;
    if (newAlbum == null) return;

    final lastSeenRaw = await _storage.read(_kLastSeenAtKey);
    final lastSeen =
        lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw) : null;

    final managed = await _buildManagedSet(systemAlbums);

    int page = 1;
    const pageSize = 100;
    while (true) {
      final resp = await _searchApi.searchAssets(
        MetadataSearchDto(
          createdAfter: lastSeen,
          withDeleted: false,
          page: page,
          size: pageSize,
        ),
      );
      if (resp == null) break;
      final ids = resp.assets.items
          .where((a) => !managed.contains(a.id))
          .map((a) => a.id)
          .toList();
      if (ids.isNotEmpty) await _albumApi.addAssets(newAlbum.id, ids);
      if (resp.assets.nextPage == null) break;
      page++;
    }

    await _storage.write(
        _kLastSeenAtKey, DateTime.now().toUtc().toIso8601String());
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
