function appId(window) {
  if (!window) return ""
  if (window.wayland && window.wayland.appId) return String(window.wayland.appId)
  var ipc = window.lastIpcObject || {}
  return String(ipc.class || ipc.initialClass || "")
}

function label(window) {
  return window && window.title ? String(window.title) : (appId(window) || "Untitled")
}

function detail(window) {
  if (!window) return ""
  var value = appId(window)
  if (window.workspace) value += (value ? " · " : "") + "ws " + String(window.workspace.id)
  return value
}

function historyRank(window) {
  var ipc = window && window.lastIpcObject ? window.lastIpcObject : {}
  var rank = Number(ipc.focusHistoryID)
  return isFinite(rank) && rank >= 0 ? rank : 1000000
}

function isCurrent(window) {
  return !!(window && window.activated) || historyRank(window) === 0
}

function focusRank(window) {
  return isCurrent(window) ? -1 : historyRank(window)
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

if (typeof module !== "undefined") module.exports = {
  appId: appId,
  label: label,
  detail: detail,
  isCurrent: isCurrent,
  sortedWindows: sortedWindows,
  filteredWindows: filteredWindows
}
