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
// Do not renumber it again: it has been applied on prod, and renaming an applied
// migration fails with "previously executed migration ... is missing". The check on
// every upstream bump is the reverse one: no *new* upstream migration may sort below
// an applied fork migration. Upstream migrations sorting above this one are fine;
// they simply run after it (v3.2.4's start at 1784647658615). Number a new fork
// migration just above the newest upstream one at that time, and list it in ORDER.
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
