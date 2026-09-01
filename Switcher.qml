import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Keyboard-first window switcher overlay with a live window peek.
//
// Opened with `omarchy-shell shell toggle piyush.omaswitch` (bind it to
// a key in ~/.config/hypr/bindings.lua). Lists Hyprland toplevels from the
// Quickshell Hyprland singleton, filters live as you type, and focuses the
// selection through the native Wayland toplevel API, with hyprctl as fallback.
//
// By default the highlighted window's live preview is the switcher: Alt+Tab
// moves through large visual cards instead of a text list. Only one window is
// captured at a time in single mode; strip mode captures the visible neighbors
// too. Set previewLayout to "single" or "list" in this plugin's shell.json
// entry to select either alternative layout.

Item {
  id: root

  property var shell: null
  property var manifest: null

  // The plugin host hides us by calling close() after removing us from
  // openPanelIds; we must not fight it, so `opened` is only our UI state.
  property bool opened: false
  property bool cycleMode: false
  property bool orderFrozen: false
  property bool cycleStarted: false
  property bool committing: false
  property int pendingDirection: 1
  property int pendingSteps: 0
  property int extraSelects: 0
  property bool workspaceOnly: false
  property int workspaceFilterId: 0
  property var cycleFrom: null
  property var mruAddrs: []
  property string filterText: ""
  property int selectedIndex: 0
  property int hoveredIndex: -1
  property int openDelayMs: 120

  // Raw toplevels (live objects from the Hyprland singleton) + filtered rows.
  property var allWindows: []
  property var rows: []

  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int listGap: Style.space(4)
  readonly property int gap: Style.space(12)
  // Match niri's recent-windows renderer. It reserves highlight padding for
  // every thumbnail, even though the gray ghost is drawn only for selection.
  readonly property int niriThumbnailGap: 16
  readonly property int niriTitleGap: 14
  readonly property int niriHighlightPadding: 30
  readonly property int niriHighlightBorder: 2
  readonly property int previewSpacing: niriThumbnailGap + (niriHighlightPadding + niriHighlightBorder) * 2

  // Guard the index: assigning a shorter rows array notifies bindings before
  // rebuildRows() gets to clamp selectedIndex.
  readonly property var selectedToplevel: selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex] : null
  readonly property bool previewWanted: root.opened && root.selectedToplevel !== null && !!root.selectedToplevel.wayland
  readonly property bool previewActive: root.previewWanted && previewView.hasContent
  property string previewLayoutMode: "strip"
  readonly property bool stripLayout: root.previewLayoutMode === "strip" && root.previewWanted
  readonly property bool singleLayout: root.previewLayoutMode === "single" && root.previewWanted
  readonly property bool visualLayout: root.stripLayout || root.singleLayout

  readonly property int cardWidth: root.stripLayout
    ? Math.max(1, panel.width - Style.gapsOut * 2)
    : Math.min(root.singleLayout ? Style.space(960) : (root.previewActive ? Style.space(1080) : Style.space(760)), panel.width - Style.gapsOut * 2)
  readonly property int desiredListHeight: Math.max(root.rowHeight, rows.length * root.rowHeight)
  readonly property int desiredCardHeight: root.contentMargin * 2 + root.headerHeight + root.listGap + root.desiredListHeight
  readonly property int cardHeight: root.stripLayout
    ? Math.min(Math.max(Style.space(650), Math.round(panel.height * 0.72)), panel.height - Style.gapsOut * 2)
    : Math.min(
        Math.max(root.singleLayout ? Style.space(560) : (root.previewActive ? Style.space(400) : 0), root.singleLayout ? 0 : root.desiredCardHeight),
        panel.height - Style.gapsOut * 2)
  readonly property int contentHeight: Math.max(0, root.cardHeight - root.contentMargin * 2)
  readonly property int innerWidth: Math.max(0, root.cardWidth - root.contentMargin * 2)
  readonly property int listWidth: root.visualLayout ? 0 : (root.previewActive ? Math.max(Style.space(300), Math.round(root.innerWidth * 0.40)) : root.innerWidth)
  readonly property int previewWidth: root.visualLayout ? root.innerWidth : (root.previewActive ? Math.max(0, root.innerWidth - root.listWidth - root.gap) : 0)
  readonly property int listHeight: Math.max(0, root.contentHeight - root.headerHeight - root.listGap)
  // Positive before the pane appears, so ScreencopyView can obtain its first
  // frame and flip hasContent without depending on a zero-sized parent.
  readonly property int previewConstraintWidth: Math.max(1, Math.min(Style.space(580), panel.width - Style.space(420)))
  readonly property int previewConstraintHeight: Math.max(1, Math.min(Style.space(360), panel.height - Style.gapsOut * 2 - root.contentMargin * 2))
  readonly property int previewCaptionHeight: root.niriTitleGap + Style.font.body
  readonly property int previewAreaHeight: Math.max(1, root.contentHeight - root.previewCaptionHeight - Style.space(8))
  readonly property int previewMinimumWidth: Math.max(Style.space(180), Math.round(root.innerWidth * 0.12))
  readonly property int previewMaximumWidth: Math.max(root.previewMinimumWidth, Math.round((root.innerWidth - root.previewSpacing * 2) / 3))
  readonly property int previewStripContentWidth: root.previewWidthsTotal()
  readonly property int previewStripInset: Math.max(0, Math.round((root.innerWidth - root.previewStripContentWidth) / 2))

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  function refreshPluginSettings() {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var plugins = config && config.plugins ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === "piyush.omaswitch") {
        var value = plugins[i].previewLayout
        // Backward compatibility: false was list, true was the original
        // visual/single-preview mode.
        if (value === false || value === "list") root.previewLayoutMode = "list"
        else if (value === true || value === "single") root.previewLayoutMode = "single"
        else root.previewLayoutMode = "strip"
        var configuredDelay = Number(plugins[i].openDelayMs)
        root.openDelayMs = isFinite(configuredDelay) && configuredDelay >= 0
          ? Math.min(1000, configuredDelay) : 120
        return
      }
    }
    root.previewLayoutMode = "strip"
    root.openDelayMs = 120
  }

  onShellChanged: root.refreshPluginSettings()

  Connections {
    target: root.shell
    function onShellConfigChanged() { root.refreshPluginSettings() }
  }

  Component.onCompleted: root.refreshPluginSettings()

  onSelectedIndexChanged: {
    if (root.stripLayout && visualStrip.count > 0)
      Qt.callLater(root.positionVisualStrip)
  }

  function positionVisualStrip() {
    if (!root.stripLayout || visualStrip.count <= 0) return
    var before = 0
    var after = 0
    for (var i = 0; i < root.selectedIndex; i++) before += root.previewWidthFor(root.rows[i]) + root.previewSpacing
    for (var j = root.selectedIndex + 1; j < root.rows.length; j++) after += root.previewWidthFor(root.rows[j]) + root.previewSpacing
    var selectedWidth = root.previewWidthFor(root.rows[root.selectedIndex])
    var sideSpace = Math.max(0, (visualStrip.width - selectedWidth) / 2)
    var canCenter = before >= sideSpace && after >= sideSpace
    visualStrip.positionViewAtIndex(root.selectedIndex, canCenter ? ListView.Center : ListView.Contain)
  }

  function previewWidthFor(window) {
    return Model.previewWidth(window, root.previewAreaHeight, root.previewMinimumWidth, root.previewMaximumWidth)
  }

  function previewHeightFor(window) {
    return Math.min(root.previewAreaHeight, Math.max(1, Math.round(root.previewWidthFor(window) / Model.aspectRatio(window))))
  }

  function previewWidthsTotal() {
    if (!root.rows || root.rows.length === 0) return 0
    var total = (root.rows.length - 1) * root.previewSpacing
    for (var i = 0; i < root.rows.length; i++) total += root.previewWidthFor(root.rows[i])
    return total
  }

  function rebuildRows() {
    var source = allWindows
    if (root.workspaceOnly) {
      source = source.filter(function(window) {
        var workspace = window && window.workspace
        if (!workspace && window && window.lastIpcObject) workspace = window.lastIpcObject.workspace
        return workspace && Number(workspace.id) === root.workspaceFilterId
      })
    }
    rows = Model.filteredWindows(source, filterText)
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
    if (selectedIndex < 0 && rows.length > 0) selectedIndex = 0
  }

  function setFilter(value) {
    filterText = value
    selectedIndex = 0
    rebuildRows()
  }

  function normAddr(value) {
    return Model.normalizeAddress(value)
  }

  function refresh() {
    allWindows = Model.sortedWindows(Hyprland.toplevels.values)
    rebuildRows()
  }

  function applyMruOrder() {
    if (!root.mruAddrs.length) return
    var orderIndex = ({})
    for (var o = 0; o < root.mruAddrs.length; o++) orderIndex[root.mruAddrs[o]] = o
    var source = allWindows && typeof allWindows.slice === "function" ? allWindows.slice() : []
    source.sort(function(left, right) {
      function idx(w) {
        var a = root.normAddr(w && w.address)
        return orderIndex.hasOwnProperty(a) ? orderIndex[a] : 1000000
      }
      return idx(left) - idx(right)
    })
    allWindows = source
    rebuildRows()
  }

  function applyHyprRanks(jsonText) {
    var clients = []
    try { clients = JSON.parse(jsonText || "[]") } catch (e) { return }
    var ranked = []
    for (var i = 0; i < clients.length; i++) {
      var addr = root.normAddr(clients[i].address)
      var rank = Number(clients[i].focusHistoryID)
      if (addr && isFinite(rank) && rank >= 0) ranked.push({ addr: addr, rank: rank })
    }
    ranked.sort(function(a, b) { return a.rank - b.rank })
    var hyprOrder = []
    for (var r = 0; r < ranked.length; r++) hyprOrder.push(ranked[r].addr)
    root.mruAddrs = Model.mruMerge(root.mruAddrs, hyprOrder)
    root.applyMruOrder()
    var currentAddr = hyprOrder[0]
    if (currentAddr) {
      var w
      for (w = 0; w < root.rows.length; w++) {
        if (root.normAddr(root.rows[w].address) === currentAddr) {
          root.cycleFrom = root.rows[w]
          break
        }
      }
    }
    if (root.extraSelects === 0) {
      root.cycleStarted = false
      root.startCycle(root.pendingDirection)
    }
    root.orderFrozen = true
  }

  function indexOfToplevel(target) {
    if (!target || root.rows.length === 0) return -1
    var needle = root.normAddr(target.address)
    var i
    for (i = 0; i < root.rows.length; i++) {
      if (root.rows[i] === target) return i
      if (needle && root.normAddr(root.rows[i].address) === needle) return i
    }
    return -1
  }

  function startCycle(direction) {
    if (root.cycleStarted) return
    if (root.rows.length === 0) return
    var from = root.cycleFrom
    var cur = root.indexOfToplevel(from)
    // Focused window is not slot 0 until ranks land. Skipping index 0 then
    // highlights the still-focused window. Wait until we know its address.
    if (cur < 0) return
    root.cycleStarted = true
    cycleFallback.stop()
    if (root.rows.length === 1) {
      root.selectedIndex = 0
      revealDelay.restart()
      return
    }
    var steps = root.pendingSteps
    if (!steps) steps = direction < 0 ? -1 : 1
    var dir = steps < 0 ? -1 : 1
    var n = Math.abs(steps)
    var next = cur
    var i
    for (i = 0; i < n; i++) {
      next = (next + dir + root.rows.length) % root.rows.length
      if (from && (root.rows[next] === from || root.normAddr(root.rows[next].address) === root.normAddr(from.address)))
        next = (next + dir + root.rows.length) % root.rows.length
    }
    root.selectedIndex = next
    // Selection is ready immediately, but do not map the overlay or begin any
    // screencopy streams unless Alt remains held past the reveal delay.
    revealDelay.restart()
  }

  function focusWindow(window) {
    if (!window) return
    var cmd = Model.focusCommand(window)
    if (cmd) Quickshell.execDetached(["bash", "-c", cmd])
    else if (window.wayland && typeof window.wayland.activate === "function")
      window.wayland.activate()
  }

  function focusSelected() {
    if (root.committing) return
    var window = rows[selectedIndex]
    if (!window) return root.dismiss()
    root.committing = true
    root.mruAddrs = Model.mruBump(
      root.mruAddrs,
      root.normAddr(root.cycleFrom && root.cycleFrom.address),
      root.normAddr(window.address)
    )
    var target = window
    root.dismiss()
    Qt.callLater(function() { root.focusWindow(target) })
  }

  function select(delta) {
    if (rows.length === 0) return
    root.extraSelects += 1
    selectedIndex = (selectedIndex + delta + rows.length) % rows.length
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var direction = Number(payload.direction) < 0 ? -1 : 1
    var workspaceCycle = payload.mode === "cycle-workspace"

    if (payload.mode === "commit") {
      cycleFallback.stop()
      revealDelay.stop()
      if (root.committing) return
      if (!root.cycleStarted && !root.cycleMode) return
      if (!root.cycleStarted) root.startCycle(root.pendingDirection)
      if (!root.cycleStarted) return
      root.focusSelected()
      return
    }
    if (payload.mode === "cancel") {
      root.dismiss()
      return
    }

    // Repeated Alt+Tab: accumulate steps before the overlay exists so a
    // fast double-tab is not treated as a fresh cycle (which would reset).
    if ((payload.mode === "cycle" || workspaceCycle) && (root.opened || root.cycleMode)) {
      root.cycleMode = true
      if (root.cycleStarted) root.select(direction)
      else root.pendingSteps += direction
      root.pendingDirection = direction
      return
    }

    // Snapshot Hyprland's real focusHistoryID, then switch, then show the
    // overlay. Ranking from Quickshell `activated` is stale for Electron.
    root.committing = false
    root.cycleFrom = null
    root.cycleMode = payload.mode === "cycle" || workspaceCycle
    root.orderFrozen = false
    root.cycleStarted = false
    root.pendingDirection = direction
    root.pendingSteps = direction
    root.extraSelects = 0
    root.workspaceOnly = workspaceCycle
    root.workspaceFilterId = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 0
    root.filterText = ""
    root.selectedIndex = 0
    root.hoveredIndex = -1
    root.refresh()
    if (root.cycleMode) {
      rankProc.running = false
      rankProc.running = true
      cycleFallback.restart()
    } else {
      root.opened = true
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function leaveSubmap() {
    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")'])
  }

  function close() {
    root.opened = false
    revealDelay.stop()
    root.cycleMode = false
    root.orderFrozen = false
    root.cycleStarted = false
    root.pendingSteps = 0
    root.extraSelects = 0
    root.hoveredIndex = -1
    root.cycleFrom = null
    root.leaveSubmap()
  }

  // User-initiated dismissal also drops the host's openPanelIds entry.
  function dismiss() {
    root.opened = false
    revealDelay.stop()
    root.cycleMode = false
    root.orderFrozen = false
    root.cycleStarted = false
    root.pendingSteps = 0
    root.extraSelects = 0
    root.hoveredIndex = -1
    root.cycleFrom = null
    root.leaveSubmap()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "piyush.omaswitch")
  }

  // Frozen Alt+Tab order: do not re-sort on activewindow. Live-focusing the
  // highlighted row (and Electron apps like t3code) would reshuffle LRU while
  // the overlay is open and send the just-chosen window to the bottom.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened || root.orderFrozen) return
      var name = event ? String(event.name || "") : ""
      if (name === "closewindow" || name === "openwindow") root.refresh()
    }
  }

  Process {
    id: rankProc
    running: false
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.applyHyprRanks(text)
    }
  }

  Timer {
    id: cycleFallback
    interval: 50
    repeat: true
    onTriggered: {
      if (root.cycleStarted || !root.cycleMode) { stop(); return }
      root.startCycle(root.pendingDirection)
    }
  }

  Timer {
    id: revealDelay
    interval: root.openDelayMs
    repeat: false
    onTriggered: {
      if (!root.cycleStarted || !root.cycleMode || root.committing) return
      // Mapping the panel first lets ListView create visible delegates; their
      // ScreencopyViews then fill independently as compositor frames arrive.
      root.opened = true
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "piyush-omaswitch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.stripLayout ? Qt.rgba(0, 0, 0, 0.72) : root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.stripLayout ? "transparent" : root.background
      borderSpec: root.stripLayout
        ? Border.surfaceSpec("menu", "border", "transparent", 0)
        : root.borderSpec

      Row {
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: root.gap

        Column {
          visible: !root.visualLayout
          width: root.listWidth
          height: parent.height
          spacing: root.listGap

          Text {
            text: root.filterText === "" ? "Switch window…" : "Filter: " + root.filterText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
            width: parent.width
          }

          ListView {
            id: listView
            width: parent.width
            height: root.listHeight
            model: root.rows
            currentIndex: root.selectedIndex
            clip: true

            Text {
              parent: listView
              anchors.centerIn: parent
              visible: root.rows.length === 0
              text: root.filterText ? "No matching windows" : "No windows"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            delegate: Item {
              required property var modelData
              required property int index
              width: listView.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: index === root.selectedIndex || index === root.hoveredIndex ? root.selectedBackground : "transparent"
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                width: parent.width - Style.space(20)
                spacing: 2

                Text {
                  text: Model.label(modelData)
                  textFormat: Text.PlainText
                  color: index === root.selectedIndex || index === root.hoveredIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  text: Model.detail(modelData)
                  textFormat: Text.PlainText
                  color: index === root.selectedIndex || index === root.hoveredIndex ? root.selectedText : root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.hoveredIndex = index
                onExited: { if (root.hoveredIndex === index) root.hoveredIndex = -1 }
                onClicked: { root.selectedIndex = index; root.focusSelected() }
              }
            }
          }
        }

        // Niri-style recent-windows strip: a few large live previews remain
        // visible together while the selected MRU window stays centered.
        ListView {
          id: visualStrip
          visible: root.stripLayout
          width: root.stripLayout ? root.innerWidth : 0
          height: parent.height
          orientation: ListView.Horizontal
          spacing: root.previewSpacing
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex
          leftMargin: root.previewStripInset
          rightMargin: root.previewStripInset
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            required property var modelData
            required property int index
            width: root.previewWidthFor(modelData)
            height: visualStrip.height
            z: index === root.selectedIndex ? 2 : (index === root.hoveredIndex ? 1 : 0)

            Rectangle {
              // Niri's active highlight is a gray background behind the
              // preview and title, extended by 30 logical pixels. The slot
              // spacing above reserves this room even while unselected.
              anchors.fill: previewColumn
              anchors.margins: -root.niriHighlightPadding
              visible: index === root.selectedIndex || index === root.hoveredIndex
              color: index === root.selectedIndex ? "#999999" : Qt.rgba(0.6, 0.6, 0.6, 0.45)
              border.color: color
              border.width: root.niriHighlightBorder
            }

            Column {
              id: previewColumn
              width: parent.width
              height: root.previewHeightFor(modelData) + root.previewCaptionHeight
              anchors.centerIn: parent
              spacing: root.niriTitleGap

              Item {
                width: parent.width
                height: root.previewHeightFor(modelData)
                clip: true

                ScreencopyView {
                  id: stripPreview
                  anchors.fill: parent
                  captureSource: modelData && modelData.wayland ? modelData.wayland : null
                  live: root.opened && !!captureSource
                  paintCursor: false
                  constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
                }

              }

              Text {
                width: parent.width
                text: Model.label(modelData)
                textFormat: Text.PlainText
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: index === root.selectedIndex || index === root.hoveredIndex
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: previewColumn
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.hoveredIndex = index
              onExited: { if (root.hoveredIndex === index) root.hoveredIndex = -1 }
              onClicked: { root.selectedIndex = index; root.focusSelected() }
            }
          }
        }

        // One large preview, retained as a middle option between the Niri-like
        // strip and the original searchable list.
        Column {
          visible: root.singleLayout
          width: root.singleLayout ? root.innerWidth : 0
          height: parent.height
          spacing: Style.space(8)

          BorderSurface {
            width: parent.width
            height: Math.max(1, parent.height - singleCaption.height - parent.spacing)
            radius: root.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.25)
            borderSpec: Border.surfaceSpec("popups", "border", root.selectedBackground, Math.max(1, Style.space(2)))
            clip: true

            ScreencopyView {
              anchors.centerIn: parent
              captureSource: root.previewWanted ? root.selectedToplevel.wayland : null
              live: root.previewWanted
              paintCursor: false
              constraintSize: Qt.size(Math.max(1, parent.width), Math.max(1, parent.height))
            }
          }

          Column {
            id: singleCaption
            width: parent.width
            spacing: 2

            Text {
              width: parent.width
              text: root.selectedToplevel ? Model.label(root.selectedToplevel) : ""
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.selectedToplevel
                ? Model.detail(root.selectedToplevel) + (root.filterText ? " · filter: " + root.filterText : "")
                : ""
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }
        }

        // Right-side peek pane. Only visible once the view actually has a
        // frame; width collapses to 0 and the list takes the whole card when
        // the compositor cannot export windows.
        Column {
          visible: root.previewLayoutMode === "list" && root.previewActive
          width: root.previewWidth
          height: parent.height
          spacing: 0

          BorderSurface {
            width: parent.width
            height: parent.height
            radius: root.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.25)
            borderSpec: Border.surfaceSpec("popups", "border", root.border, Math.max(1, Style.space(1)))
            clip: true

            ScreencopyView {
              id: previewView
              anchors.centerIn: parent
              captureSource: root.previewWanted ? root.selectedToplevel.wayland : null
              live: root.previewWanted
              paintCursor: false
              constraintSize: Qt.size(root.previewConstraintWidth, root.previewConstraintHeight)
            }
          }
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      z: 1
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.focusSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
          root.select((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      // Best-effort native Alt-Tab behavior. If the compositor delivers the
      // modifier release after granting this overlay focus, commit selection.
      Keys.onReleased: function(event) {
        if (!root.committing && root.cycleMode && (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta)) {
          root.focusSelected()
          event.accepted = true
        }
      }
    }
  }
}
