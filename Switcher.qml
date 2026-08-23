import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Keyboard-first window switcher overlay.
//
// Opened with `omarchy-shell shell toggle piyush.window-switcher` (bind it to
// a key in ~/.config/hypr/bindings.lua). Lists Hyprland toplevels from the
// Quickshell Hyprland singleton, filters live as you type, and focuses the
// selection with a hyprctl dispatch (same call omarchy's own focus helpers use).
//
// v1 scope, deliberately small: no thumbnails, no MRU ordering, no per-workspace
// groups. It lists all mapped toplevels once, keeps the order Hyprland reports
// them in, and lets typing do the narrowing.

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // The plugin host hides us by calling close() after removing us from
  // openPanelIds; we must not fight it, so `opened` is only our UI state.
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0

  // Raw toplevels (live objects from the Hyprland singleton) + filtered rows.
  property var allWindows: []
  property var rows: []

  readonly property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(rows.length * rowHeight + Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2), panel.height - Style.gapsOut * 2)
  readonly property int contentMargin: Style.spacing.panelPadding

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  function windowLabel(w) {
    return w && w.title ? String(w.title) : (w && w.appId ? String(w.appId) : "Untitled")
  }

  function windowDetail(w) {
    if (!w) return ""
    var detail = w.appId ? String(w.appId) : ""
    if (w.workspace) detail += (detail ? " · " : "") + "ws " + String(w.workspace.id)
    return detail
  }

  function rebuildRows() {
    var q = filterText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < allWindows.length; i++) {
      var w = allWindows[i]
      if (!w) continue
      var label = windowLabel(w)
      if (q && label.toLowerCase().indexOf(q) === -1) continue
      out.push(w)
    }
    rows = out
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
    if (selectedIndex < 0 && rows.length > 0) selectedIndex = 0
  }

  function refresh() {
    allWindows = Hyprland.toplevels.values.slice()
    rebuildRows()
  }

  function focusSelected() {
    var w = rows[selectedIndex]
    if (!w || !w.address) {
      root.close()
      return
    }
    var cmd = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:" + w.address + "\" })")
    Quickshell.execDetached(cmd)
    root.close()
  }

  function select(delta) {
    if (rows.length === 0) return
    selectedIndex = (selectedIndex + delta + rows.length) % rows.length
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // Keep the list fresh while open (windows open/close/rename).
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened) return
      var name = event ? String(event.name || "") : ""
      if (name === "activewindow" || name === "closewindow" || name === "openwindow" || name === "workspace") {
        root.refresh()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "piyush-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec

      Column {
        anchors.fill: parent
        anchors.margins: root.contentMargin

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
          height: Math.min(rows.length * root.rowHeight, card.height - Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2) - root.contentMargin * 2)
          model: root.rows
          clip: true

          delegate: Item {
            required property var modelData
            required property int index
            width: listView.width
            height: root.rowHeight

            Rectangle {
              anchors.fill: parent
              radius: root.cornerRadius
              color: index === root.selectedIndex ? root.selectedBackground : "transparent"
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              width: parent.width - Style.space(20)
              spacing: 2

              Text {
                text: root.windowLabel(modelData)
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
              }
              Text {
                text: root.windowDetail(modelData)
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: { root.selectedIndex = index; root.focusSelected() }
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
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.focusSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.text === "k") {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.text === "j") {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          if (root.filterText.length > 0) {
            root.filterText = root.filterText.slice(0, -1)
            root.rebuildRows()
          }
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.filterText += event.text
          root.rebuildRows()
          event.accepted = true
        }
      }
    }
  }
}
