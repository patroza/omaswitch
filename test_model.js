const assert = require("node:assert/strict")
const Model = require("./Model.js")

const active = { title: "Browser", activated: true, wayland: { appId: "chromium" }, workspace: { id: 1 }, lastIpcObject: { focusHistoryID: 0 } }
const previous = { title: "Terminal", activated: false, wayland: { appId: "foot" }, workspace: { id: 2 }, lastIpcObject: { focusHistoryID: 1 } }
const old = { title: "Notes", activated: false, lastIpcObject: { class: "obsidian", focusHistoryID: 8 }, workspace: { id: 3 } }

assert.deepEqual(Model.sortedWindows([old, previous, active]), [active, previous, old])
assert.equal(Model.isCurrent(active), true)
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: { focusHistoryID: 0 } }), true)
assert.deepEqual(Model.filteredWindows([active, previous, old], "foot"), [previous])
assert.deepEqual(Model.filteredWindows([active, previous, old], "notes"), [old])
assert.equal(Model.detail(old), "obsidian · ws 3")
assert.equal(Model.aspectRatio({ lastIpcObject: { size: [1920, 1080] } }), 16 / 9)
assert.equal(Model.aspectRatio({ lastIpcObject: { size: { x: 900, y: 1600 } } }), 0.5625)
assert.equal(Model.previewWidth({ lastIpcObject: { size: [900, 1600] } }, 600, 180, 540), 338)
assert.equal(Model.previewWidth({ lastIpcObject: { size: [1920, 1080] } }, 600, 180, 540), 540)
assert.equal(Model.label({ title: "x".repeat(161) }), "x".repeat(159) + "…")
assert.equal(Model.detail({ wayland: { appId: "x".repeat(161) } }), "x".repeat(159) + "…")

// --- focusCommand: switching to windows on other workspaces ---
// Reproduces the bug: confirming a selection previously used the native
// activate path, which focuses the window but does NOT move to its workspace,
// and the plain `focuswindow` fallback dropped the 0x address prefix, so the
// lookup silently missed. Verifies the fix always dispatches an explicit,
// workspace-switching command.
const target = { title: "Browser", address: "55ea685ceda0", workspace: { id: 5 } }
const targetHex = { title: "Browser", address: "0x55ea685ceda0", workspace: { id: 5 } }
const expected = "hyprctl dispatch \"hl.dsp.focus({ window = 'address:0x55ea685ceda0' })\" >/dev/null 2>&1 || hyprctl dispatch focuswindow \"address:0x55ea685ceda0\""

assert.ok(Model.focusCommand(target), "window with address must produce a dispatch command")
assert.equal(Model.focusCommand(target), expected, "address must be normalized with 0x prefix")
assert.equal(Model.focusCommand(targetHex), expected, "existing 0x prefix must be preserved")
assert.ok(Model.focusCommand(target).startsWith("hyprctl dispatch \"hl.dsp.focus("),
  "primary dispatch must be the workspace-switching hl.dsp.focus form")
assert.ok(Model.focusCommand(target).includes("|| hyprctl dispatch focuswindow \"address:0x55ea685ceda0\""),
  "plain focuswindow must remain as the stock-Hyprland fallback")
assert.equal(Model.focusCommand({}), null, "no address defers to native activate fallback")
assert.equal(Model.focusCommand(null), null, "no window defers to native activate fallback")
console.log("Model checks passed")

// --- MRU ordering: unranked windows (no meaningful focusHistoryID) ---
// Hyprland reports focusHistoryID: null / "" for windows not meaningfully in
// the focus history (transient/popup clients). Number(null) === 0 and
// Number("") === 0, so the old historyRank() wrongly ranked them as the
// current window (rank 0), surfacing stale windows above genuinely recent
// ones and mislabeling them as current. They must sort AFTER all ranked
// windows, in source order, and never be treated as current.
const editorCur = { title: "Editor", activated: true, lastIpcObject: { focusHistoryID: 0 }, wayland: { appId: "ed" } }
const termPrev = { title: "Term", activated: false, lastIpcObject: { focusHistoryID: 1 }, wayland: { appId: "foot" } }
const staleNull = { title: "StalePopup", activated: false, lastIpcObject: { focusHistoryID: null }, wayland: { appId: "popup" } }
const staleEmpty = { title: "Mystery", activated: false, lastIpcObject: { focusHistoryID: "" }, wayland: { appId: "unknown" } }
const staleBlank = { title: "Blank", activated: false, lastIpcObject: { focusHistoryID: " " }, wayland: { appId: "blank" } }

assert.deepEqual(
  Model.sortedWindows([termPrev, editorCur, staleNull, staleEmpty, staleBlank]).map(function(w) { return w.title }),
  ["Editor", "Term", "StalePopup", "Mystery", "Blank"],
  "unranked windows must sort AFTER ranked ones, in source order"
)

assert.equal(Model.isCurrent(staleNull), false, "null focusHistoryID must not be current")
assert.equal(Model.isCurrent(staleEmpty), false, "empty focusHistoryID must not be current")
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: {} }), false, "missing focusHistoryID must not be current")
assert.equal(Model.isCurrent(editorCur), true, "activated window must be current")
assert.equal(Model.isCurrent({ activated: false, lastIpcObject: { focusHistoryID: 0 } }), true, "real rank 0 must be current")

const staleActivated = { title: "StaleActive", activated: true, lastIpcObject: { focusHistoryID: 5 } }
const realRecent = { title: "Recent", activated: false, lastIpcObject: { focusHistoryID: 1 } }
assert.deepEqual(
  Model.sortedWindows([staleActivated, realRecent]).map(function(w) { return w.title }),
  ["Recent", "StaleActive"],
  "activated must not outrank a better focusHistoryID"
)

// --- commit-only MRU: skipped windows must not become previous ---
const C = "0xc"
const T = "0xt3"
const D = "0xd"
let mru = [C, T, D]
mru = Model.mruBump(mru, C, T)
mru = Model.mruBump(mru, T, C)
assert.deepEqual(mru, [C, T, D], "chromium ↔ t3 ping-pong")
mru = Model.mruBump(mru, C, D)
assert.deepEqual(mru, [D, C, T], "skip t3, commit discord")
mru = Model.mruBump(mru, D, C)
assert.deepEqual(mru, [C, D, T], "tab back to chromium; next is discord not t3")
assert.deepEqual(
  Model.mruMerge([D, C, T], [D, T, C]),
  [D, C, T],
  "peek-polluted hypr focusHistory must not override commit order"
)
assert.deepEqual(
  Model.mruMerge([D, C, T], [T, D, C]),
  [T, D, C],
  "clicking t3 takes compositor order"
)
assert.deepEqual(Model.mruMerge([], [C, T, D]), [C, T, D], "empty ours seeds from hypr")
assert.equal(Model.normalizeAddress("abc"), "0xabc")
assert.equal(Model.normalizeAddress("0xAbC"), "0xabc")
