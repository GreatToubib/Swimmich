# Camembert Handover

A single-file phone app for running a camembert handover queue: names in an
ordered list, sliced into fixed-length time slots, with payment and handover
tracked per line.

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
slot length, or capacity re-times the whole queue. Defaults are 21:30, 2 per
slot, 15 minutes — all three are editable under Settings.

Per line: name, optional note, payment (`to pay` / `paid`), and handover
(`waiting` / `handed over`).

## Interactions

- **Add** — name field pinned at the bottom; appends to the tail.
- **Edit** — tap a line to open the sheet (name, note, payment, handover, delete).
- **Handover** — the tick button on each line, one tap, no sheet.
- **Reorder** — drag the grip. Pointer-events based, so touch and mouse take the
  same path; the list reflows live and a gold drop marker shows the landing
  position. Dragging near a screen edge auto-scrolls.
- **Undo** — deletes and *clear all* are recoverable from the snackbar for 6s.
- **Copy list** — plain-text dump of the queue for pasting into a message.

## Notes for future edits

- Pointer capture is deliberately taken on `<body>`, not on the grip: every
  reorder re-renders the board, which would destroy the grip mid-drag and kill
  the event stream.
- Dashed borders mean "nothing here yet" (free seat, drop target). A handed-over
  line stays solid and is quieted instead — don't make it dashed.
- Class names are flat and unscoped, so check for collisions before adding one.
  `.pip.empty` once inherited padding from an unrelated `.empty` empty-state
  rule and rendered as an 82px oval.
