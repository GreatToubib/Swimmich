import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<any>): Promise<void> {
  await sql`DELETE FROM "album" WHERE "systemKind" IS NOT NULL;`.execute(db);
  await sql`DROP INDEX IF EXISTS "UQ_album_owner_systemKind";`.execute(db);
  await sql`ALTER TABLE "album" DROP COLUMN "systemKind";`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`ALTER TABLE "album" ADD "systemKind" text;`.execute(db);
  await sql`CREATE UNIQUE INDEX "UQ_album_owner_systemKind" ON "album" ("ownerId", "systemKind") WHERE "systemKind" IS NOT NULL;`.execute(db);
}
