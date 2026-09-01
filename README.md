# OmaSwitch

**A familiar `Alt+Tab` switcher for Omarchy—with live window previews.**

OmaSwitch puts your recently used windows in one fast, keyboard-first overlay. Cycle through large live previews with `Alt+Tab`, type to find one by name, and release Alt to switch.

![OmaSwitch showing a live terminal preview](preview.png)

## Why you will like it

- **Recent windows first.** Uses Hyprland focus history, so the window you want is usually next.
- **Visual by default.** Alt+Tab scrolls through several large live window previews side by side instead of a text list.
- **Natural window shapes.** Preview cards preserve each window's real aspect ratio, so portrait windows stay tall and narrow while landscape windows stay wide.
- **Niri-style presentation.** Strip mode floats previews directly over a dark translucent backdrop, without menu or card boxes.
- **Made for the keyboard.** Repeat `Alt+Tab`, search by typing, use arrows or Tab, then press Enter.
- **Niri-style context.** Neighboring MRU windows remain visible while the selected preview stays centered.
- **Fits Omarchy.** Follows your active Omarchy theme and needs no daemon, packages, or privileges.

## See it in action

### Pick the project window without leaving the keyboard

Search or cycle through windows, then confirm with Enter (or release Alt when the compositor forwards the release event).

![OmaSwitch with a project terminal preview](screenshots/terminal-preview.png)

### Check a live `btop` preview before switching

The preview changes with the selected row, making similarly named windows easy to distinguish.

![OmaSwitch with a live btop preview](screenshots/btop-preview.png)

## Add it to Omarchy

```bash
omarchy plugin add https://github.com/piyush97/omaswitch.git --enable
```

It installs in your user configuration and needs no extra package, service, or configuration file.

The Niri-style preview strip is enabled by default. Three layouts are available
through the plugin entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "piyush.omaswitch", "previewLayout": "strip" }
```

- `"strip"`: several live previews side by side (default)
- `"single"`: one large live preview
- `"list"`: searchable text list with a side preview

The older boolean values remain compatible: `true` selects `single` and
`false` selects `list`.

The overlay waits 120 ms by default before appearing. A quick Alt+Tab therefore
switches immediately without mapping the panel or starting window capture. To
adjust that threshold, add `"openDelayMs": 120` to the plugin entry. Once the
panel appears, preview streams populate asynchronously.

> Live previews require Hyprland's `hyprland-toplevel-export-v1` protocol. If it is unavailable, switching and search still work; the plugin simply uses its list-only layout.

## Make it your Alt+Tab switcher

Omarchy binds `Alt+Tab` to direct cycling by default. Add this to `~/.config/hypr/bindings.lua` to replace those two bindings:

```lua
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

o.bind("ALT + TAB", "OmaSwitch", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":1}'")
o.bind("ALT + SHIFT + TAB", "OmaSwitch (reverse)", "omarchy-shell shell summon piyush.omaswitch '{\"mode\":\"cycle\",\"direction\":-1}'")
```

Then reload Hyprland:

```bash
hyprctl reload
hyprctl configerrors
```

`configerrors` should print no errors. If you want to keep Omarchy's default bindings, bind either summon command to another key instead.

## Familiar from the first keypress

| Shortcut | What it does |
| --- | --- |
| `Alt+Tab` | Open the switcher and move to the next recent window |
| `Alt+Shift+Tab` | Open the switcher and move backward |
| `Tab`, `Down`, `Right` | Select the next window |
| `Shift+Tab`, `Up`, `Left` | Select the previous window |
| Type | Filter by title, application, or workspace |
| `Backspace` / `Ctrl+Backspace` | Delete a character / word from the search |
| `Ctrl+U` | Clear the search |
| `Enter` or click | Focus the selected window |
| `Esc` or click outside | Close without switching |

To open the searchable picker directly:

```bash
omarchy-shell shell toggle piyush.omaswitch
```

## Keep it current

```bash
omarchy plugin update piyush.omaswitch --yes
```

To disable or remove it:

```bash
omarchy plugin disable piyush.omaswitch
omarchy plugin remove piyush.omaswitch --yes
```

## Troubleshooting

**The plugin is not listed**

```bash
omarchy-shell shell rescanPlugins
omarchy plugin list --json
```

**Alt+Tab still directly cycles windows**

Confirm that the original bindings were unbound, then run:

```bash
hyprctl reload
hyprctl configerrors
omarchy menu keybindings --print | grep -E 'ALT \+ TAB|SHIFT ALT \+ TAB|OmaSwitch'
```

**The plugin opens without window images**

The windows may not be capturable, or `hyprland-toplevel-export-v1` may be unavailable. Set `previewLayout` to `"list"` to use the text-first layout on such a system.

**The plugin reports a QML error**

```bash
journalctl --user -f | grep -Ei 'piyush.omaswitch|Switcher.qml|qml.*(error|warning)'
```

## Development

```bash
node test_model.js
omarchy plugin validate .
git diff --check
```

The plugin is MIT licensed; see [LICENSE](LICENSE). It is an independent community plugin and is not affiliated with Omarchy.
