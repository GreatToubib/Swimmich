# File des camemberts

A single-file phone app for running a camembert handover: an ordered list of
named lines, sliced into fixed-length time slots, with payment and handover
tracked per line. The interface is in French; this file is the developer note.

Not part of the Immich fork — it shares nothing with `mobile/` and needs no
build step. `index.html` is the whole app: no dependencies, no network calls,
no server.

## Running it

Open `index.html` in any modern browser. On a phone, either serve the folder
over the LAN (`python3 -m http.server 8000`) and browse to it, or open the file
and add it to the home screen for a full-screen launcher.

State lives in `localStorage` under `camembert-handover-v1`, so the queue
survives reloads and is scoped to that one browser on that one device. There is
no sync between devices — one phone is the source of truth. If `localStorage`
is unavailable (private mode, blocked storage), the app still runs, but the
queue is lost on reload.

## Model

Lines are one flat ordered array. Slot times are *derived* from position, never
stored:

```
slot(i)  = floor(i / perSlot)
time(i)  = startTime + slot(i) × slotMinutes
```

So reordering a line re-times everything after it, and changing the start time,
slot length, or capacity re-times the whole queue. Defaults are 21h30, 2 per
slot, 15 minutes — all three are editable under *Réglages*.

Per line: name, optional note, payment (`à payer` / `payé`), handover
(`en attente` / `remis`), and an optional **desired time** (`heure souhaitée`).

The desired time is a *request*, not a result. It is picked from a list starting
at the configured first slot and stepping 15 minutes, and it never moves a line
— position alone decides the real handover time. When the derived time lands
later than the wish, the line's chip turns amber and shows the gap (`souhait
21h30 · +30 min`), which is the cue to drag the line earlier. Reordering clears
the flag on its own.

## Sharing (read-only snapshots)

There is no server, so a share is a **frozen snapshot**, never a live feed:
readers do not see later edits. Payment status is stripped from every share
path — it is never encoded, not merely hidden.

*Partager en lecture seule* picks the best available path:

1. **Link** when the page is top-level (self-hosted): the queue is base64url
   encoded into `#s=…`. Opening that URL renders the same app in read-only mode
   — no grips, no add bar, no settings, no payment, and it never writes to the
   reader's `localStorage`.
2. **File** when the page is inside a foreign iframe (the published artifact),
   where the visible URL is not this document's and a copied link would be dead.
   Generates a standalone read-only HTML page via `window.claude.downloads`.
3. **Text** if the download is refused — `html` is in the extended download set
   and may be disabled per view — or if the capability is absent.

*Copier ma liste* is the private counterpart and **does** include payments;
it's labelled as such because pasting it into a group chat would publish who
still owes money.

## Notes for future edits

- Pointer capture is deliberately taken on `<body>`, not on the grip: every
  reorder re-renders the board, which would destroy the grip mid-drag and kill
  the event stream.
- Dashed borders mean "nothing here yet" (free seat, drop target). A handed-over
  line stays solid and is quieted instead — don't make it dashed.
- Class names are flat and unscoped, so check for collisions before adding one.
  This bit twice: `.pip.empty` inherited padding from the unrelated `.empty`
  empty-state rule, then `.pip.vacant` inherited `min-height` from the free-seat
  `.vacant` rule — both times a 9px dot rendered as a large capsule. Pip
  modifiers are now prefixed (`.pip-full`, `.pip-done`, `.pip-free`). The test
  asserts every pip measures 9×9.
- `[hidden] { display: none !important }` is load-bearing: several components
  set an explicit `display: flex`, which otherwise beats the `hidden` attribute
  and left the composer visible to public readers.
- Anything added to the reader's view must be checked against the rendered DOM,
  not just styled out of sight.
