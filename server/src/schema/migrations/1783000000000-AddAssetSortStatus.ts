import { Kysely, sql } from 'kysely';

// Swimmich: adds the triage status used by the Sort deck.
//
// Renumbered from 1779400000000 during the v2.7.5 -> v3.0.3 migration. Kysely
// requires the executed migrations to be an exact prefix of the on-disk list, and
// v3 shipped ~20 upstream migrations whose timestamps predate the fork's original
// number (authored before the fork branched, released after). That left this
// migration wedged in the middle of the upstream sequence, and the server refused
// to boot with "corrupted migrations: expected previously executed migration
// 1779364515374-AddAlbumSystemKind to be at index 68".
//
// Keep fork migrations numbered above every upstream migration. Renumber again if
// a future upstream release lands anything above this value.
//
// IF NOT EXISTS so databases that already ran the old 1779400000000 copy (whose
// kysely_migrations row is deleted as part of the same fix) re-run this as a no-op.

export async function up(db: Kysely<any>): Promise<void> {
  await sql`ALTER TABLE "asset" ADD COLUMN IF NOT EXISTS "sortStatus" character varying NOT NULL DEFAULT 'new';`.execute(
    db,
  );
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`ALTER TABLE "asset" DROP COLUMN IF EXISTS "sortStatus";`.execute(db);
}
