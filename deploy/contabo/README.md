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

- Deploy: push to `swimmich`, wait for the `:prod` build, then `ssh contabo /opt/immich/src/deploy/contabo/deploy.sh`.
- Rollback: set `SWIMMICH_IMAGE` in `/opt/immich/.env` to an older `:prod-<sha>` tag and run `deploy.sh` again.
- Logs: `ssh contabo 'cd /opt/immich && docker compose logs -f --tail=100 immich-server'`.
- Backups: nightly restic snapshots to the Hetzner storage box (see the Knowledge article "Infrastructure").

Changes in `deploy/` do not trigger an image build (`paths-ignore` in `swimmich-deploy.yml`).
