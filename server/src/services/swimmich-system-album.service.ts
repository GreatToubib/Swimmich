import { OnEvent } from 'src/decorators';
import { ImmichWorker } from 'src/enum';
import { ArgOf } from 'src/repositories/event.repository';
import { BaseService } from 'src/services/base.service';

const SYSTEM_ALBUMS: { kind: string; name: string }[] = [
  { kind: 'new', name: '_New' },
  { kind: 'review_later', name: '_Review Later' },
  { kind: 'one_star', name: '⭐' },
  { kind: 'two_star', name: '⭐⭐' },
  { kind: 'three_star', name: '⭐⭐⭐' },
];

export class SwimmichSystemAlbumService extends BaseService {
  @OnEvent({ name: 'UserCreate' })
  async onUserCreate({ id }: ArgOf<'UserCreate'>) {
    await this.provisionForUser(id);
  }

  @OnEvent({ name: 'AppBootstrap', workers: [ImmichWorker.Api] })
  async backfillExistingUsers() {
    const users = await this.userRepository.getList({ withDeleted: false });
    for (const user of users) {
      try {
        await this.provisionForUser(user.id);
      } catch (error) {
        this.logger.warn(`Swimmich system album provisioning failed for user ${user.id}: ${error}`);
      }
    }
  }

  private async provisionForUser(userId: string) {
    const existing = await this.albumRepository.getOwned(userId);
    const byKind = new Map(existing.filter((a) => a.systemKind).map((a) => [a.systemKind!, a]));
    const byName = new Map(existing.map((a) => [a.albumName, a]));

    for (const { kind, name } of SYSTEM_ALBUMS) {
      if (byKind.has(kind)) {
        continue;
      }

      const adopt = byName.get(name);
      if (adopt) {
        await this.albumRepository.update(adopt.id, { systemKind: kind });
        continue;
      }

      await this.albumRepository.create({ ownerId: userId, albumName: name, systemKind: kind }, [], []);
    }
  }
}
