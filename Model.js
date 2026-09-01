var maxDisplayLength = 160

function boundedText(value) {
  value = String(value || "")
  return value.length > maxDisplayLength ? value.slice(0, maxDisplayLength - 1) + "…" : value
}

function appId(window) {
  if (!window) return ""
  if (window.wayland && window.wayland.appId) return String(window.wayland.appId)
  var ipc = window.lastIpcObject || {}
  return String(ipc.class || ipc.initialClass || "")
}

function label(window) {
  return boundedText(window && window.title ? window.title : (appId(window) || "Untitled"))
}

function detail(window) {
  if (!window) return ""
  var value = appId(window)
  if (window.workspace) value += (value ? " · " : "") + "ws " + String(window.workspace.id)
  return boundedText(value)
}

function aspectRatio(window) {
  var ipc = window && window.lastIpcObject ? window.lastIpcObject : {}
  var size = ipc.size
  var width = Array.isArray(size) ? Number(size[0]) : Number(size && (size.x || size.width))
  var height = Array.isArray(size) ? Number(size[1]) : Number(size && (size.y || size.height))
  if (!(width > 0) || !(height > 0)) return 16 / 9
  return Math.max(0.35, Math.min(3.2, width / height))
}

function previewWidth(window, availableHeight, minimumWidth, maximumWidth) {
  var natural = Math.round(Math.max(1, Number(availableHeight) || 1) * aspectRatio(window))
  return Math.max(Number(minimumWidth) || 1, Math.min(Number(maximumWidth) || natural, natural))
}

// Hyprland's focusHistoryID is a rank in the compositor's global focus-history
// list: 0 = currently focused, 1 = most recent before that, ascending = older.
// Transient/popup windows not meaningfully in that history can report null or
// an empty string. Number(null) === 0 and Number("") === 0, so we must guard
// before coercion — otherwise such windows are ranked 0 (treated as current)
// and surface above genuinely recent ones.
function historyRank(window) {
  var ipc = window && window.lastIpcObject ? window.lastIpcObject : {}
  var raw = ipc.focusHistoryID
  if (raw === null || raw === undefined) return 1000000
  // "" and " " both coerce to 0; discard empty/whitespace values (transient
  // windows not meaningfully in the focus history).
  if (typeof raw !== "number" && String(raw).trim() === "") return 1000000
  var rank = Number(raw)
  return isFinite(rank) && rank >= 0 ? rank : 1000000
}

function isCurrent(window) {
  return !!(window && window.activated) || historyRank(window) === 0
}

function focusRank(window) {
  // Do not boost `activated`: Electron clients often leave that flag set on
  // several windows at once, which scrambled MRU order. Rank is compositor
  // focusHistoryID only.
  return historyRank(window)
}

function sortedWindows(values) {
  var source = values && typeof values.slice === "function" ? values.slice() : []
  var decorated = []
  for (var i = 0; i < source.length; i++) decorated.push({ value: source[i], index: i })
  decorated.sort(function(left, right) {
    return focusRank(left.value) - focusRank(right.value) || left.index - right.index
  })
  var result = []
  for (var j = 0; j < decorated.length; j++) result.push(decorated[j].value)
  return result
}

function filteredWindows(values, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return values.slice()
  return values.filter(function(window) {
    return (label(window) + " " + detail(window)).toLowerCase().indexOf(q) !== -1
  })
}

// Build the shell command that focuses a window AND moves to its workspace.
// Native toplevel activate does not always switch the visible workspace, so
// the switch is requested explicitly: prefer Omarchy's Lua dispatcher form
// (hl.dsp.focus), fall back to the plain focuswindow syntax for stock
// Hyprland. Returns null when the window has no address, deferring to the
// native activate path in Switcher.qml.
function focusCommand(window) {
  var raw = window && window.address
  if (raw === null || raw === undefined || raw === "") return null
  var rawAddress = String(raw)
  var address = rawAddress.indexOf("0x") === 0 ? rawAddress : "0x" + rawAddress
  return "hyprctl dispatch \"hl.dsp.focus({ window = 'address:" + address +
    "' })\" >/dev/null 2>&1 || hyprctl dispatch focuswindow \"address:" + address + "\""
}

function normalizeAddress(value) {
  var a = String(value || "").toLowerCase()
  if (a && a.indexOf("0x") !== 0) a = "0x" + a
  return a
}

function mruPush(out, seen, value) {
  var a = normalizeAddress(value)
  if (!a || seen[a]) return
  seen[a] = true
  out.push(a)
}

// Commit only: move `to` to front and `from` to second. Skipped windows keep
// their relative order — Hyprland's focusHistoryID cannot un-record a peek.
function mruBump(order, fromAddr, toAddr) {
  var out = []
  var seen = ({})
  mruPush(out, seen, toAddr)
  mruPush(out, seen, fromAddr)
  if (order) {
    for (var i = 0; i < order.length; i++) mruPush(out, seen, order[i])
  }
  return out
}

// Trust our commit-order while the compositor's current window still matches.
// If the user focused something outside Alt+Tab, take Hyprland's list instead.
function mruMerge(ours, hypr) {
  var compositor = []
  var oursNorm = []
  var seenHypr = ({})
  var seenOurs = ({})
  var i
  if (hypr) {
    for (i = 0; i < hypr.length; i++) mruPush(compositor, seenHypr, hypr[i])
  }
  if (ours) {
    for (i = 0; i < ours.length; i++) mruPush(oursNorm, seenOurs, ours[i])
  }
  if (!compositor.length) return oursNorm
  if (!oursNorm.length || oursNorm[0] !== compositor[0]) return compositor
  var inHypr = ({})
  for (i = 0; i < compositor.length; i++) inHypr[compositor[i]] = true
  var out = []
  var seen = ({})
  for (i = 0; i < oursNorm.length; i++) {
    if (inHypr[oursNorm[i]]) mruPush(out, seen, oursNorm[i])
  }
  for (i = 0; i < compositor.length; i++) mruPush(out, seen, compositor[i])
  return out
}

if (typeof module !== "undefined") module.exports = {
  appId: appId,
  label: label,
  detail: detail,
  aspectRatio: aspectRatio,
  previewWidth: previewWidth,
  isCurrent: isCurrent,
  sortedWindows: sortedWindows,
  filteredWindows: filteredWindows,
  focusCommand: focusCommand,
  normalizeAddress: normalizeAddress,
  mruBump: mruBump,
  mruMerge: mruMerge
}
