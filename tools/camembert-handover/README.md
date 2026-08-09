# File des camemberts

A phone app for running a camembert handover: an ordered list of named lines,
sliced into fixed-length time slots, with payment and handover tracked per line.
The interface is in French; this file is the developer note.

It is an **installable, offline-first PWA**. Once installed it has a home-screen
icon, opens without browser chrome, and runs with no network at all. Nothing is
sent anywhere — no server, no account, no analytics, no requests of any kind
after the initial load.

Not part of the Immich fork: it shares nothing with `mobile/` and has no build
step or dependencies.

```
index.html              the whole app (markup, styles, logic)
sw.js                   service worker — makes it work offline
manifest.webmanifest    name, icons, standalone display
icon-*.png              generated app icons
test*.mjs               Playwright suites
```

## Getting it onto the phone

A service worker only registers in a **secure context**, so the app has to be
served over HTTPS (or `localhost`) *once*. A LAN address like
`http://192.168.1.20:8000` is not a secure context and will not install — it
will load, but stay online-only. `file://` is worse: no service worker, and
browsers isolate or block its storage.

After that one load, everything is cached and the network is never needed again.

### GitHub Pages (no server to run)

The repo is public, so Pages is free. Two ways:

1. **Deploy from a branch** — Settings → Pages → Source *Deploy from a branch*,
   pick the branch and `/ (root)`. The app lands at
   `https greattoubib.github.io/Swimmich/tools/camembert-handover/`. Add an empty
   `.nojekyll` at the repo root first, or Jekyll will try to build the whole fork.
2. **Workflow** (cleaner) — Settings → Pages → Source *GitHub Actions*, then use
   `.github/workflows/camembert-pages.yml` in this repo. It publishes only this
   folder, so the app sits at `https://greattoubib.github.io/Swimmich/` and the
   rest of the fork is not exposed. It runs on pushes touching this folder, and
   on demand.

### The OVH VPS

Caddy already terminates HTTPS there. Copy this folder to the box and add a
route — a `file_server` on a subdomain or a path — then open it once on the
phone. Check `df -h /home/basil` first; the box is shared and this needs ~40 kB.

### Installing

- **Android / Chrome** — an *Installer sur l'écran d'accueil* button appears in
  Réglages when the browser offers it, or use ⋮ → *Ajouter à l'écran d'accueil*.
- **iOS / Safari** — Share → *Sur l'écran d'accueil*. iOS gives no install
  button, so the app doesn't show one there; the manifest and icons still apply.

## Storage, and why you should still export

The queue lives in `localStorage` under `camembert-handover-v1`, on that one
device in that one browser. The app calls `navigator.storage.persist()` to ask
the browser not to evict it, and Réglages reports whether that was granted.

Even so, the data is only as durable as the browser profile: clearing site data,
uninstalling, or a browser cleanup under storage pressure takes it with it.
There is no server copy. So:

- **Sauvegarde** writes a timestamped `.json` to the phone's downloads. If the
  browser refuses the download, the JSON is copied to the clipboard instead.
- **Restaurer** accepts that file, or pasted text. It takes either a JSON backup
  or the plain list produced by *Copier ma liste*, which is the migration path
  from the older claude.ai version. Restoring replaces the queue and is undoable
  from the snackbar; unrecognised input is refused without touching anything.

A JSON file cannot be the live database, by the way: no mobile browser exposes
read/write access to a file on disk (the File System Access API is absent on
Android Chrome and iOS Safari). Hence browser storage as the store, JSON as the
portable copy.

## Model

Lines are one flat ordered array. Slot times are *derived* from position, never
stored:

```
slot(i)  = floor(i / perSlot)
time(i)  = startTime + slot(i) × slotMinutes
```

So reordering a line re-times everything after it, and changing the start time,
slot length, or capacity re-times the whole queue. Defaults are 21h30, 2 per
slot, 15 minutes — all editable under *Réglages*.

Per line: name, optional note, payment (`à payer` / `payé`), handover
(`en attente` / `remis`), and an optional desired time (`heure souhaitée`).

Payment and handover are both one tap on the line itself. The rest is in the
edit sheet, opened by tapping the name.

### Desired time

Picked in 15-minute steps starting from the configured first slot. It is a
*request*, not a result — position alone decides the real handover time. When
the derived time lands later than the wish, the chip turns amber and shows the
gap (`souhait 21h30 · +30 min`), which is the cue to drag the line earlier.
Reordering clears the flag on its own.

### Total cap

*Nombre de camemberts max* caps how many lines the queue may hold; `0` or empty
means no cap, the default. Once reached, adding is refused with an error — the
typed name is kept, the field is flagged, and the message offers a shortcut into
Réglages. The cap only blocks **new** lines: lowering it below the current count
deletes nothing, it warns and lets the counter read over quota (`4 / 2`). Free
seats are clamped to the remaining allowance, so a seat shown as available can
always actually be filled.

## Notes for future edits

- **Bump `CACHE` in `sw.js` whenever any cached file changes.** Otherwise the
  old version keeps being served from the cache and your edit appears to do
  nothing. `APP_VERSION` in `index.html` is shown in Réglages so you can see at
  a glance which build the phone is actually running.
- Pointer capture is deliberately taken on `<body>`, not on the grip: every
  reorder re-renders the board, which would destroy the grip mid-drag and kill
  the event stream.
- Dashed borders mean "nothing here yet" (free seat, drop target). A handed-over
  line stays solid and is quieted instead — don't make it dashed.
- Class names are flat and unscoped, so check for collisions before adding one.
  This bit twice: `.pip.empty` inherited padding from the unrelated `.empty`
  empty-state rule, then `.pip.vacant` inherited `min-height` from the free-seat
  `.vacant` rule — both times a 9px dot rendered as a large capsule. Pip
  modifiers are now prefixed (`.pip-full`, `.pip-done`, `.pip-free`), and the
  tests assert every pip measures 9×9.
- `[hidden] { display: none !important }` is load-bearing: several components
  set an explicit `display: flex`, which otherwise beats the `hidden` attribute.
- The snackbar takes real multi-line messages, so it is a rounded rectangle, not
  a `999px` pill (an ellipse once text wraps), and it is centred with
  `left/right + margin: auto` rather than `left: 50%` (which caps its
  shrink-to-fit width at half the viewport).

## Tests

```
python3 -m http.server 8899        # from this folder
node test.mjs                      # migration, toggles, desired time, drag, undo
node test-max.mjs                  # the total cap and its refusal path
node test-offline.mjs              # service worker, offline reload, backup/restore
```

`localhost` is a secure context, so `test-offline.mjs` exercises the service
worker exactly as it will behave over HTTPS: it cuts the network with
`setOffline(true)`, reloads, and checks the queue still renders and still
accepts edits — including a cold open of `start_url`, which is what the
home-screen icon does.
