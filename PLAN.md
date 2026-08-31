# omapad — plan

A lightning-fast scratchpad for Omarchy. Super+N summons a floating overlay with a text pane and a sketch pane, both backed to disk. Super+N again (or Escape) hides it. Content persists across sessions.

## Design principles

1. **Speed is everything.** `keepLoaded: true` on the overlay so summon is IPC-fast, not cold-start. No work on open beyond focusing the text field.
2. **One static note.** Not multiple notes, not a history browser. A single persistent scratchpad you keep adding to. If you want to clear it, you clear it explicitly.
3. **Keyboard first.** Everything reachable without the mouse. Escape and Super+N both hide.
4. **Copy is the point.** Two visible copy buttons plus keyboard shortcuts. Toast confirmation.

## Interaction model

| Action | Result |
|--------|--------|
| Super+N | Toggle overlay (summon if hidden, hide if visible) |
| Escape | Hide overlay |
| Ctrl+Shift+C | Copy text pane contents to clipboard |
| Ctrl+Shift+S | Copy sketch pane as PNG to clipboard |
| Ctrl+Z (in sketch) | Undo last stroke |
| Click "copy" (text) | Same as Ctrl+Shift+C |
| Click "copy" (sketch) | Same as Ctrl+Shift+S |
| Click "clear" (sketch) | Wipe canvas (with confirm if non-empty) |
| Type in text pane | Autosaves after 400ms idle |
| Draw in sketch pane | Autosaves stroke on mouse up |

The text field receives focus on open. Cursor position is preserved across sessions.

## UI layout

Floating card, centered, sized like the clipboard manager (~875×600 max, shrinks on small screens). Split 50/50 into two panes with a vertical divider.

```
┌─ Omapad ─────────────────────────────────────┐
│                                              │
│  Text                    │  Sketch    [copy] │
│                  [copy]  │                   │
│  ┌────────────────────┐  │  ┌──────────────┐ │
│  │                    │  │  │              │ │
│  │  editable text     │  │  │  canvas      │ │
│  │  ...               │  │  │              │ │
│  │                    │  │  │              │ │
│  └────────────────────┘  │  └──────────────┘ │
│                          │      [clear]      │
└──────────────────────────────────────────────┘
```

## Architecture

**Plugin kind:** `overlay` — matches clipboard/emojis. Not a bar widget, no bar anchor needed. Full-viewport panel with a scrim and a centered card.

**Plugin ID:** `jamespember.omapad` (dev id `dhh.omapad`-style; permanent id set before publish).

**Directory layout:**

```
omapad/
├── manifest.json      overlay entry point, keepLoaded: true
├── Omapad.qml         root Item, PanelWindow, key catcher, both panes
├── TextPane.qml       TextArea + copy button + autosave
├── SketchPane.qml     Canvas + strokes model + copy/clear buttons
├── Strokes.js         pure functions for stroke storage and rendering
├── PLAN.md            this file
├── README.md          install + usage
└── LICENSE            MIT
```

**Persistence:**

- Text pane content lives at `settings.notePath` (see Settings below). Default `~/.local/state/omapad/note.txt`. Plain text, atomic writes via `FileView`.
- `~/.local/state/omapad/sketch.json` — sketch pane strokes as `[{ points: [[x,y], ...] }, ...]`. Rendered on load into the canvas. Always local (never synced to the vault). Atomic writes.

Rationale for JSON strokes over PNG: vector data replays crisply at any DPI and lets us do undo. PNG is generated on-the-fly when copying.

Rationale for keeping sketches local while text is configurable: text is the thing you want in your knowledge system (Obsidian, Logseq, plain notes). Sketches are ephemeral — you draw, you copy, you move on. If v2 needs sketch-to-vault-as-PNG, we can add it.

## Settings

Per the Omarchy shell contract, settings live inline on the plugin entry in `~/.config/omarchy/shell.json` under the top-level `plugins: []` array. The plugin reads them from shell.json via `FileView` with `watchChanges: true`, so edits take effect without a shell restart.

**Schema (v1):**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `notePath` | string | `~/.local/state/omapad/note.txt` | File where the text pane persists. `~` and `$HOME` are expanded. Parent directory is created if missing. If the file has a Markdown extension, it's still written as plain text (Markdown formatting isn't rendered in the pane — it's just what you type). |

**Example shell.json entry for the Obsidian use case:**

```json
{
  "plugins": [
    {
      "id": "jamespember.omapad",
      "notePath": "~/Documents/Obsidian/MyVault/Scratchpad.md"
    }
  ]
}
```

**Manifest declaration (so the settings UI can render a field later):**

```json
{
  "overlay": {
    "defaults": { "notePath": "~/.local/state/omapad/note.txt" },
    "schema": [
      { "key": "notePath", "type": "string", "label": "Note file path" }
    ]
  }
}
```

**Reading in QML (rough shape):**

```qml
FileView {
  path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  watchChanges: true
  onLoaded: settings = extractSettings(text())
  onFileChanged: reload()
}

function extractSettings(raw) {
  var config = JSON.parse(raw)
  var entries = (config && config.plugins) || []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].id === "jamespember.omapad") return entries[i]
  }
  return {}
}
```

When `notePath` changes at runtime, we flush the current buffer to the old path, then swap and load from the new path (empty file if it doesn't exist yet). No data loss on retarget.

**Future settings (not v1):**

- `sketchPath` — where to persist strokes JSON
- `sketchAttachmentDir` — where to write PNGs on copy (so Obsidian users can paste a wikilink)
- `openOnStart` — always open with cursor at end vs. cursor at start
- `wordWrap` — toggle

**Copy pipeline:**

- Text → `wl-copy` via `Quickshell.execDetached(["wl-copy"], ...)` with text on stdin. Or use `omarchy-clipboard-paste-text` style helper if available — check at build time.
- Sketch → render canvas to `~/.cache/omapad/sketch-<timestamp>.png`, then `wl-copy -t image/png < file`.

## What's NOT in v1

- Multiple notes / history browser (explicitly out of scope per your call)
- Eraser, color picker, brush sizes
- Shape tools
- Search
- Sync
- Auto-copy on close
- Undo for text pane (native TextArea handles it)

## Milestones

1. **M1 — skeleton visible.** Manifest + Omapad.qml with layout. `omarchy-shell shell toggle jamespember.omapad '{}'` shows the card.
2. **M2 — text pane works.** Typing persists to disk, restores on next open, copy button + shortcut work.
3. **M3 — sketch pane works.** Draw → autosave → reload strokes. Clear + undo work. Copy PNG works.
4. **M4 — bind & polish.** Super+N in Hyprland. Toasts. Validate with `omarchy plugin validate` + `qmllint`.

## Open questions (answer later, not blockers)

- Should text pane support Markdown rendering toggle? (Probably no — keep it a pure scratchpad.)
- Should sketch color follow the theme accent, or stay `Color.menu.text`? (Start with `Color.menu.text` — matches clipboard's aesthetic.)
- Should we ship a bar widget too, for click-to-open? (Not v1 — keyboard is the story.)
