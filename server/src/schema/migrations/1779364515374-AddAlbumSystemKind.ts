import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<any>): Promise<void> {
  await sql`ALTER TABLE "album" ADD COLUMN "systemKind" text`.execute(db);
  await sql`CREATE UNIQUE INDEX "UQ_album_owner_systemKind"
    ON "album" ("ownerId", "systemKind")
    WHERE "systemKind" IS NOT NULL`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP INDEX IF EXISTS "UQ_album_owner_systemKind"`.execute(db);
  await sql`ALTER TABLE "album" DROP COLUMN IF EXISTS "systemKind"`.execute(db);
}
