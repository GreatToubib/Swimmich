# Swimmich on the Contabo VPS

Prod runs on the Contabo VPS `vmi3622327` (167.86.115.97, `ssh contabo`) in `/opt/immich`, with Docker.
CI builds the image (`ghcr.io/greattoubib/swimmich-server:prod`) on every push to `swimmich`; the VPS only pulls.

| Path on the VPS | Content |
|---|---|
| `/opt/immich/src` | sparse clone of this repository (this folder only, branch `swimmich`) |
| `/opt/immich/docker-compose.yml` | copy of `docker-compose.yml`, refreshed by `deploy.sh` |
| `/opt/immich/.env` | from `.env.example`, holds the DB password (never committed) |
| `/opt/immich/library`, `/opt/immich/postgres` | photos and database |
| `/opt/caddy/sites/immich.caddy` | copy of `immich.caddy` (HTTPS) |
| `/etc/cron.d/immich-tag-mycamera` | runs `tag-mycamera.sh` at 01:30 (API key in `/opt/immich/secrets/mycamera-curlrc`, never committed) |

- Deploy: push to `swimmich`, wait for the `:prod` build, then `ssh contabo /opt/immich/src/deploy/contabo/deploy.sh`.
  When the Immich base version changes, first set `ML_VERSION` in `/opt/immich/.env` to it.
- Before promoting an Immich upgrade, try the `:test` build on a copy of the prod database:
  [`test-stack/`](test-stack/README.md).
- Rollback: set `SWIMMICH_IMAGE` in `/opt/immich/.env` to an older `:prod-<sha>` tag and run `deploy.sh` again.
  If the new version ran database migrations, the old image refuses to start ("previously executed
  migration ... is missing"): restore the dump `deploy.sh` took first, then start the old image.

  ```bash
  cd /opt/immich && docker compose stop immich-server
  gunzip -c backups/pre-deploy-<timestamp>.sql.gz \
    | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
    | docker exec -i immich-postgres psql -U postgres -d postgres -q   # "current user cannot be dropped" / "role postgres already exists": expected
  sed -i 's#^SWIMMICH_IMAGE=.*#SWIMMICH_IMAGE=ghcr.io/greattoubib/swimmich-server:prod-<sha>#' .env   # and ML_VERSION back
  docker compose up -d
  ```
- Logs: `ssh contabo 'cd /opt/immich && docker compose logs -f --tail=100 immich-server'`.
- Backups: nightly restic snapshots to the Hetzner storage box (see the Knowledge article "Infrastructure").

Changes in `deploy/` do not trigger an image build (`paths-ignore` in `swimmich-deploy.yml`).
