# Temporary test stack next to prod (Contabo)

Runs a CI-built `:test` image against a **copy** of the prod database on `127.0.0.1:2284`, to check an
upgrade (migrations, API, the phone app) before promoting it. Prod keeps running untouched: the copy has
its own Postgres and Redis, the prod library is mounted read-only and only the API worker runs, so no job
can write, move or delete prod files. It lives in `/opt/immich-test`, which neither `deploy.sh` nor the
nightly backup looks at. Tear it down when done.

Rehearsed on 2026-10-01 with Docker Desktop: today's `:prod` image (v3.0.3) as the source and a v3.2.4
build as `:test`.

## 1. Bring it up (`ssh contabo`)

```bash
git -C /opt/immich/src pull --ff-only     # brings this folder
mkdir -p /opt/immich-test && cd /opt/immich-test
install -m 644 /opt/immich/src/deploy/contabo/test-stack/docker-compose.yml docker-compose.yml
install -m 600 /opt/immich/src/deploy/contabo/test-stack/.env.example .env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(openssl rand -hex 16)/" .env
sed -i "s#^SWIMMICH_IMAGE=.*#SWIMMICH_IMAGE=ghcr.io/greattoubib/swimmich-server:test-<sha>#" .env
docker compose pull -q
docker compose up -d database redis
```

`<sha>` is the first 7 characters of the `swimmich-test` commit that CI built (`:test-<sha>` tag).

## 2. Copy the prod database

A plain `pg_dump` carries no roles, so the copy keeps its own password. The `sed` is Immich's documented
fix for dumps that reset `search_path`.

```bash
cd /opt/immich-test
until docker exec immich-test-postgres pg_isready -U postgres -q; do sleep 2; done
docker exec immich-postgres pg_dump -U postgres -d immich --clean --if-exists | gzip > prod-copy.sql.gz
gunzip -c prod-copy.sql.gz \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker exec -i immich-test-postgres psql -U postgres -d immich -v ON_ERROR_STOP=1 -q > restore.log
```

Both lines must match:

```bash
Q='select (select count(*) from "user"), (select count(*) from asset), (select count(*) from album), (select max(name) from kysely_migrations)'
for c in immich-postgres immich-test-postgres; do docker exec "$c" psql -U postgres -d immich -At -c "$Q"; done
```

## 3. Start the server

```bash
docker compose up -d immich-server
docker compose logs -f immich-server      # until "Immich Server is listening ... [vX.Y.Z]"
curl -fsS http://127.0.0.1:2284/api/server/version
```

Expected in the log: `Running migrations`, one `Migration "..." succeeded` per new migration, then
`Finished running migrations`. Because the library is read-only it also logs
`Failed to write .../encoded-video/.immich` and `Ignoring mount folder errors`: harmless here. Any other
ERROR is a finding. Smart search and face recognition do not work on this stack (no ML container).

## 4. Use it from the phone

No DNS or Caddy change needed. On the PC, keep a tunnel open with `ssh -N -L 2284:127.0.0.1:2284 contabo`,
then with the phone on adb run `adb reverse tcp:2284 tcp:2284`. In Swimmich, log out and log in to
`http://localhost:2284` with your usual account.

Before that, on the phone, turn **off** backup (uploads would fail against the read-only library) and the
Sort setting that deletes the local copy (it deletes real files on the phone, whatever the server).
Everything done on the test server is thrown away at teardown.

## 5. Tear down

```bash
cd /opt/immich-test && docker compose down -v           # -v: Redis's anonymous volume (prod's are another project)
docker rmi "$(sed -n 's/^SWIMMICH_IMAGE=//p' .env)"   # only the :test image: postgres/valkey are prod's too
cd / && rm -rf /opt/immich-test
```

Then point the app back to `https://swimmich.azestysolution.com`.
