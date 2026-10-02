#!/usr/bin/env bash
# Swimmich prod on the Contabo VPS: pull the deploy files (this folder) and the CI-built image, then
# recreate the stack. Run after the :prod image is built (push to `swimmich`):
#   ssh contabo /opt/immich/src/deploy/contabo/deploy.sh
# Rollback: set SWIMMICH_IMAGE in /opt/immich/.env to an older :prod-<sha> tag and run it again.
set -euo pipefail

STACK=/opt/immich
cd "$STACK"

git -C src pull --ff-only -q
git -C src log -1 --format=">> deploy files: %h %s"
install -m 644 src/deploy/contabo/docker-compose.yml docker-compose.yml

echo ">> database dump before the update (3 last kept in $STACK/backups)"
mkdir -p backups
docker exec immich-postgres pg_dumpall --clean --if-exists -U postgres | gzip > "backups/pre-deploy-$(date +%Y%m%d-%H%M%S).sql.gz"
find backups -maxdepth 1 -name 'pre-deploy-*.sql.gz' -printf '%T@ %p\n' | sort -rn | tail -n +4 | cut -d' ' -f2- \
  | xargs -r rm --

echo ">> pulling images"
docker compose pull -q
echo ">> recreating the stack"
docker compose up -d --remove-orphans

# Compose does not always notice that the mutable :prod tag now points at a new image (seen with
# Compose 5.5.1 on 2026-10-02: "up -d" kept the old container and the deploy looked fine). Compare
# the running server image with the pulled one and recreate the server explicitly when they differ.
image=$(sed -n 's/^SWIMMICH_IMAGE=//p' .env)
wanted=$(docker image inspect "$image" --format '{{.Id}}')
running=$(docker inspect immich-server --format '{{.Image}}' 2>/dev/null || true)
if [ "$running" != "$wanted" ]; then
  echo ">> compose kept the previous server image, recreating immich-server"
  docker compose up -d --force-recreate --no-deps immich-server
fi
echo ">> server image: $image (${wanted#sha256:})" | cut -c1-120

for _ in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null 2>&1; then
    echo ">> OK: Immich answers on 127.0.0.1:2283"
    docker image prune -f >/dev/null || true
    exit 0
  fi
  sleep 3
done
echo "!! Immich did not answer within 2 minutes" >&2
docker compose ps
exit 1
