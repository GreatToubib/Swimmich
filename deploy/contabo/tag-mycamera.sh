#!/usr/bin/env bash
# Tags every asset shot on one of Basil's own devices with "MyCamera".
#
# Runs nightly from cron (/etc/cron.d/immich-tag-mycamera on the Contabo VPS).
# Idempotent: a full re-scan every night, because
# back-dated imports (Google Takeout) land with old capture dates but recent
# createdAt, so a "since yesterday" window would miss them. Assets that already
# carry the tag come back as duplicates and are not re-written.
#
# Uses a scoped API key (asset.read + tag.read/create/asset only) and talks to
# Immich over loopback, so it never leaves the box.
set -euo pipefail

API="http://127.0.0.1:2283/api"
# The key lives in a curl config file rather than a bare secret we splice into
# an -H argument: this box is shared, and argv is world-readable via ps.
CURL_CFG="/opt/immich/secrets/mycamera-curlrc"
LOG="/var/log/immich-tag-mycamera.log"
TAG="MyCamera"
MAKES=("OnePlus" "samsung")

log() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"; }

# Keep the log bounded - the box is shared and tight on disk.
trim_log() {
  if [[ -f "$LOG" ]] && [[ $(wc -l <"$LOG") -gt 200 ]]; then
    tail -n 200 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

if [[ ! -r "$CURL_CFG" ]]; then
  log "ERROR: missing or unreadable curl config $CURL_CFG"
  exit 1
fi

# api <method> <path> [json-body]
api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS --max-time 120 -K "$CURL_CFG" -X "$method" "$API$path" \
      -H 'Content-Type: application/json' -d "$body"
  else
    curl -fsS --max-time 120 -K "$CURL_CFG" -X "$method" "$API$path"
  fi
}

# 1. Upsert the tag and resolve its id.
tag_id="$(api PUT /tags "$(jq -nc --arg t "$TAG" '{tags:[$t]}')" |
  jq -r --arg t "$TAG" '.[] | select(.value==$t) | .id')"
if [[ -z "$tag_id" || "$tag_id" == "null" ]]; then
  log "ERROR: could not resolve the $TAG tag id"
  exit 1
fi

# 2. Collect the asset ids for each camera make, paging until exhausted.
ids="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$ids" "$tmpdir"' EXIT

for make in "${MAKES[@]}"; do
  page=1
  while :; do
    resp="$(api POST /search/metadata \
      "$(jq -nc --arg m "$make" --argjson p "$page" '{make:$m,size:1000,page:$p}')")"
    jq -r '.assets.items[].id' <<<"$resp" >>"$ids"
    next="$(jq -r '.assets.nextPage // empty' <<<"$resp")"
    [[ -n "$next" ]] || break
    page="$next"
  done
done

sort -u -o "$ids" "$ids"
total="$(wc -l <"$ids")"

if [[ "$total" -eq 0 ]]; then
  log "no matching assets found - nothing to do"
  trim_log
  exit 0
fi

# 3. Bulk-tag in chunks of 500.
split -l 500 "$ids" "$tmpdir/chunk."
newly=0
for f in "$tmpdir"/chunk.*; do
  body="$(jq -Rn --arg t "$tag_id" '[inputs] | {tagIds:[$t], assetIds:.}' <"$f")"
  n="$(api PUT /tags/assets "$body" | jq -r '.count // 0')"
  newly=$((newly + n))
done

log "scanned $total assets from [${MAKES[*]}] - newly tagged $newly"
trim_log
