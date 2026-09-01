import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

// Omapad — a lightning-fast scratchpad overlay for Omarchy.
// Text pane on the left, sketch pane on the right. Both persist to disk.
// Summon and dismiss via `omarchy-shell shell toggle io.github.jamespember.omapad`.
Item {
  id: root

  // Injected by the shell when it summons the overlay.
  property var shell: null
  property var manifest: null

  property bool opened: false

  // ---- theme (borrowed from menu tokens, like clipboard/emojis) ------------
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)

  // ---- paths ---------------------------------------------------------------
  property string home: Quickshell.env("HOME")
  property string shellConfigPath: home + "/.config/omarchy/shell.json"
  property string defaultNotePath: home + "/.local/state/omapad/note.txt"
  property string sketchPath: home + "/.local/state/omapad/sketch.json"
  // notePath is the current effective location — either user-configured or default.
  property string notePath: defaultNotePath
  property string copyTextTmpPath: "/tmp/omapad-copy-text.txt"
  property string copySketchTmpPath: "/tmp/omapad-copy-sketch.png"

  // ---- shared content state (bound by the panes) ---------------------------
  property string textContent: ""
  property var strokes: []

  // ---- toast feedback ------------------------------------------------------
  property string toastMessage: ""
  Timer {
    id: toastTimer
    interval: 1400
    repeat: false
    onTriggered: root.toastMessage = ""
  }
  function toast(message) {
    root.toastMessage = String(message || "")
    toastTimer.restart()
  }

  // ---- lifecycle -----------------------------------------------------------
  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() {
      if (textPane.item) textPane.item.focusEditor()
    })
  }

  function close() {
    if (textPane.item) textPane.item.flush()
    if (sketchPane.item) sketchPane.item.flush()
    root.opened = false
  }

  function toggle() {
    if (root.opened) close()
    else open("{}")
  }

  // ---- copy pipeline -------------------------------------------------------
  // Text: base64-encode in argv, decode + wl-copy in the shell. base64 output
  // is shell-safe so no quoting hell.
  function copyText() {
    if (!root.textContent || root.textContent.length === 0) {
      root.toast("Nothing to copy")
      return
    }
    var encoded = Qt.btoa(root.textContent)
    Quickshell.execDetached(["sh", "-c", "printf %s " + encoded + " | base64 -d | wl-copy"])
    root.toast("Text copied")
  }

  function copySketch() {
    if (sketchPane.item) sketchPane.item.copyAsPng()
  }

  // ---- settings ------------------------------------------------------------
  // Read our own entry from ~/.config/omarchy/shell.json. If notePath changes
  // we flush pending writes to the old location, then swap.
  function applySettings(raw) {
    var settings = Storage.extractPluginSettings(raw, "io.github.jamespember.omapad")
    var candidate = settings.notePath
    var nextPath = candidate
      ? Storage.expandPath(String(candidate), root.home)
      : root.defaultNotePath
    if (nextPath && nextPath !== root.notePath) {
      if (textPane.item) textPane.item.flush()
      root.notePath = nextPath
    }
  }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("{}")
    onFileChanged: reload()
  }

  // Ensure parent directories exist for the note and sketch files. Runs once
  // at startup and again whenever notePath changes.
  Process {
    id: mkdirProc
    running: false
  }
  function ensureDirs() {
    mkdirProc.command = ["mkdir", "-p",
      Storage.dirname(root.notePath),
      Storage.dirname(root.sketchPath)]
    mkdirProc.running = true
  }
  Component.onCompleted: ensureDirs()
  onNotePathChanged: ensureDirs()

  // ---- overlay window ------------------------------------------------------
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omapad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // Click outside the card to close.
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
      padding: root.contentMargin

      // Eat clicks on the card so the outside-close MouseArea doesn't fire.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Title row
        Item {
          width: parent.width
          height: Style.space(28)

          Text {
            text: "Omapad"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
          }

          // Toast, right-aligned in the title row.
          Text {
            text: root.toastMessage
            color: root.foreground
            opacity: root.toastMessage.length > 0 ? 0.85 : 0
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            Behavior on opacity {
              NumberAnimation { duration: 200 }
            }
          }
        }

        // Panes
        Item {
          width: parent.width
          height: parent.height - Style.space(28) - root.contentSpacing

          Row {
            anchors.fill: parent
            spacing: 0

            Loader {
              id: textPane
              width: (parent.width - Style.space(1)) / 2
              height: parent.height
              source: Qt.resolvedUrl("TextPane.qml")
              onLoaded: item.host = root
            }

            Rectangle {
              width: Style.space(1)
              height: parent.height
              color: Util.alpha(root.border, 0.28)
            }

            Loader {
              id: sketchPane
              width: (parent.width - Style.space(1)) / 2
              height: parent.height
              source: Qt.resolvedUrl("SketchPane.qml")
              onLoaded: item.host = root
            }
          }
        }
      }
    }
  }
}
