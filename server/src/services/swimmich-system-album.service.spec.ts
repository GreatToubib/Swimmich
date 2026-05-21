import { SwimmichSystemAlbumService } from 'src/services/swimmich-system-album.service';
import { AlbumFactory } from 'test/factories/album.factory';
import { UserFactory } from 'test/factories/user.factory';
import { getForAlbum } from 'test/mappers';
import { newTestService, ServiceMocks } from 'test/utils';

describe(SwimmichSystemAlbumService.name, () => {
  let sut: SwimmichSystemAlbumService;
  let mocks: ServiceMocks;

  beforeEach(() => {
    ({ sut, mocks } = newTestService(SwimmichSystemAlbumService));
  });

  describe('onUserCreate', () => {
    it('provisions all 5 system albums for a new user', async () => {
      const user = UserFactory.create();
      mocks.album.getOwned.mockResolvedValue([]);
      mocks.album.create.mockResolvedValue(getForAlbum(AlbumFactory.create({ ownerId: user.id })));

      await sut.onUserCreate(user as any);

      expect(mocks.album.create).toHaveBeenCalledTimes(5);
      expect(mocks.album.create).toHaveBeenCalledWith(
        expect.objectContaining({ ownerId: user.id, systemKind: 'new' }),
        [],
        [],
      );
      expect(mocks.album.create).toHaveBeenCalledWith(
        expect.objectContaining({ ownerId: user.id, systemKind: 'review_later' }),
        [],
        [],
      );
    });

    it('is idempotent — skips already provisioned kinds', async () => {
      const user = UserFactory.create();
      const existing = [
        AlbumFactory.create({ ownerId: user.id, systemKind: 'new' }),
        AlbumFactory.create({ ownerId: user.id, systemKind: 'review_later' }),
        AlbumFactory.create({ ownerId: user.id, systemKind: 'one_star' }),
        AlbumFactory.create({ ownerId: user.id, systemKind: 'two_star' }),
        AlbumFactory.create({ ownerId: user.id, systemKind: 'three_star' }),
      ];
      mocks.album.getOwned.mockResolvedValue(existing.map(getForAlbum));

      await sut.onUserCreate(user as any);

      expect(mocks.album.create).not.toHaveBeenCalled();
      expect(mocks.album.update).not.toHaveBeenCalled();
    });
  });

  describe('backfillExistingUsers', () => {
    it('adopts an existing album whose name matches the canonical name', async () => {
      const user = UserFactory.create();
      const newAlbum = AlbumFactory.create({ ownerId: user.id, albumName: '_New', systemKind: null });
      mocks.user.getList.mockResolvedValue([user as any]);
      mocks.album.getOwned.mockResolvedValue([getForAlbum(newAlbum)]);
      mocks.album.update.mockResolvedValue(getForAlbum(newAlbum));
      mocks.album.create.mockResolvedValue(getForAlbum(AlbumFactory.create({ ownerId: user.id })));

      await sut.backfillExistingUsers();

      expect(mocks.album.update).toHaveBeenCalledWith(newAlbum.id, { systemKind: 'new' });
      // The other 4 should be created since no matching albums exist.
      expect(mocks.album.create).toHaveBeenCalledTimes(4);
    });
  });
});
