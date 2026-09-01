# Omapad

A lightning-fast scratchpad overlay for [Omarchy](https://github.com/basecamp/omarchy). Summon with one key, jot text or sketch, dismiss with the same key. Content persists across sessions.

- **Text pane** — a single always-open note. Autosaves as you type.
- **Sketch pane** — freehand canvas with undo and clear. Copy as PNG.
- **Zero cold start** — `keepLoaded: true`, so summon is IPC-fast.
- **Vault-friendly** — point `notePath` at your Obsidian vault to have your scratchpad show up as a Markdown file in your knowledge system.

## Install

```sh
omarchy plugin add https://github.com/jamespember/omapad.git --enable
```

Then add a binding in `~/.config/hypr/bindings.conf`:

```conf
bindd = SUPER, N, Omapad, exec, omarchy-shell shell toggle io.github.jamespember.omapad '{}'
```

Reload Hyprland (`hyprctl reload`) and hit `Super+N`.

## Use

| Keys | What it does |
|------|--------------|
| `Super+N` | Toggle the overlay |
| `Esc` | Hide |
| `Ctrl+Shift+C` | Copy the text pane |
| `Ctrl+Shift+S` | Copy the sketch pane as PNG |
| `Ctrl+Z` (in sketch) | Undo last stroke |

Both panes also have visible `copy` buttons. The sketch pane has a `clear` button that wipes the canvas after confirming it isn't empty.

## Configure

The easiest way to configure Omapad is the **cog icon** in the top-right of the overlay — it opens a small settings form with a note-path field, an editor command field, and one-click preset chips for Omawrite, Obsidian, Typora, VS Code, Neovim, and the system default. Save applies immediately.

Settings are stored inline on the plugin entry in `~/.config/omarchy/shell.json` and can also be hand-edited there:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `notePath` | string | `~/.local/state/omapad/note.txt` | File where the text pane persists. `~` and `$HOME` are expanded. |
| `openCommand` | array of strings | `["omawrite", "{path}"]` | argv template for the "open file" button. `{path}` is replaced with the absolute path; `{pathUri}` with the URI-encoded path. |

Changes to `shell.json` are picked up live — no shell restart needed. If you change `notePath` while typing, the current buffer is flushed to the old path before the new one loads.

Sketches always live locally at `~/.local/state/omapad/sketch.json`. If you want a sketch in your vault, hit the copy button and paste.

### Recipes

**Omawrite (default)** — Omarchy Quattro's stock Markdown editor:

```json
{ "id": "io.github.jamespember.omapad", "openCommand": ["omawrite", "{path}"] }
```

**Obsidian** — hand the file back to Obsidian via its URI scheme. Works even when `xdg-mime` mis-detects `.md` as `text/plain`:

```json
{
  "id": "io.github.jamespember.omapad",
  "notePath": "~/Documents/MyVault/Scratchpad.md",
  "openCommand": ["xdg-open", "obsidian://open?path={pathUri}"]
}
```

**Typora**:

```json
{ "id": "...", "openCommand": ["typora", "{path}"] }
```

**VS Code**:

```json
{ "id": "...", "openCommand": ["code", "{path}"] }
```

**Neovim (kitty + nvim)**:

```json
{ "id": "...", "openCommand": ["kitty", "nvim", "{path}"] }
```

**System handler** — set `openCommand` to `["xdg-open", "{path}"]` and it'll dispatch through your mime associations.

## Remove

```sh
omarchy plugin remove io.github.jamespember.omapad
```

## Hacking

The plugin folder can be symlinked from a working checkout into
`~/.config/omarchy/plugins/io.github.jamespember.omapad` for edit-in-place
development. Saving a source file triggers a manifest rescan
(`Local plugin changed, reloading:` in the shell log), but because the
manifest has `keepLoaded: true` for zero-latency summon, the running
overlay window is **not** re-instantiated. To pick up QML changes, restart
the shell:

```sh
omarchy-restart-shell
```

Small tweaks (labels, colors) can wait until the next summon; anything
structural (layout, new elements) needs the restart.

## License

MIT — see [LICENSE](LICENSE).
