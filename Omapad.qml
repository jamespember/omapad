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
  property bool showSettings: false

  // Raw notePath as the user wrote it in shell.json (may still contain ~).
  // Kept alongside the expanded absolute `notePath` so the settings editor
  // can round-trip user input without expanding surprises.
  property string rawNotePath: "~/.local/state/omapad/note.txt"

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

  // openCommand: argv template used by the "open file" button. Two
  // placeholders are substituted: {path} → absolute path, {pathUri} →
  // URI-encoded path (for obsidian:// and similar scheme handlers).
  // Default: omawrite (Omarchy's stock Markdown editor). Falls through to
  // xdg-open if omawrite isn't on PATH — see the README for other recipes.
  readonly property var defaultOpenCommand: ["omawrite", "{path}"]
  property var openCommand: defaultOpenCommand

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
    // Always open into the notes view; settings is a per-summon menu.
    root.showSettings = false
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

  function toggleSettings() {
    root.showSettings = !root.showSettings
    if (!root.showSettings && textPane.item) {
      Qt.callLater(function() { textPane.item.focusEditor() })
    }
  }

  // ---- copy pipeline -------------------------------------------------------
  // Text: base64-encode in argv, decode + wl-copy in the shell. base64 output
  // is shell-safe so no quoting hell.
  function copyText() {
    if (!root.textContent || root.textContent.length === 0) {
      root.toast("Nothing to copy")
      return
    }
    // Qt.btoa on strings is deprecated in Qt 6; hand it a Uint8Array of UTF-8
    // bytes. TextEncoder is available in Quickshell's JS engine.
    var encoded
    try {
      encoded = Qt.btoa(new TextEncoder().encode(root.textContent))
    } catch (e) {
      encoded = Qt.btoa(root.textContent)  // fallback if TextEncoder is missing
    }
    Quickshell.execDetached(["sh", "-c", "printf %s " + encoded + " | base64 -d | wl-copy"])
    root.toast("Text copied")
  }

  function copySketch() {
    if (sketchPane.item) sketchPane.item.copyAsPng()
  }

  // Open the note using the configured openCommand template. Placeholders
  // {path} and {pathUri} are substituted with the absolute path and its
  // URI-encoded form respectively. See README for editor recipes.
  function openFile() {
    if (textPane.item) textPane.item.flush()
    var path = root.notePath
    var uri = encodeURIComponent(path)
    var template = Array.isArray(root.openCommand) && root.openCommand.length > 0
      ? root.openCommand
      : root.defaultOpenCommand
    var argv = []
    for (var i = 0; i < template.length; i++) {
      var arg = String(template[i])
      arg = arg.split("{path}").join(path)
      arg = arg.split("{pathUri}").join(uri)
      argv.push(arg)
    }
    Quickshell.execDetached(argv)
    root.toast("Opening file")
    root.close()
  }

  // Open the parent directory in the user's file manager.
  function openFileLocation() {
    Quickshell.execDetached(["xdg-open", Storage.dirname(root.notePath)])
    root.toast("Opening folder")
    root.close()
  }

  // ---- settings ------------------------------------------------------------
  // Read our own entry from ~/.config/omarchy/shell.json. If notePath changes
  // we flush pending writes to the old location, then swap.
  function applySettings(raw) {
    var settings = Storage.extractPluginSettings(raw, "io.github.jamespember.omapad")

    var candidate = settings.notePath
    root.rawNotePath = candidate ? String(candidate) : "~/.local/state/omapad/note.txt"
    var nextPath = candidate
      ? Storage.expandPath(String(candidate), root.home)
      : root.defaultNotePath
    if (nextPath && nextPath !== root.notePath) {
      if (textPane.item) textPane.item.flush()
      root.notePath = nextPath
    }

    if (Array.isArray(settings.openCommand) && settings.openCommand.length > 0) {
      root.openCommand = settings.openCommand
    } else {
      root.openCommand = root.defaultOpenCommand
    }
  }

  // Save updates to our entry in ~/.config/omarchy/shell.json. FileView's
  // watcher then reloads and applySettings picks the changes up live.
  function saveSettings(updates) {
    var current = shellConfigFile.text()
    var next = Storage.updatePluginSettings(current, "io.github.jamespember.omapad", updates)
    shellConfigFile.setText(next)
    root.toast("Settings saved")
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

        // Title row: title on the left, toast + icon actions on the right.
        Item {
          id: titleRow
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

          // Right-side action buttons. Absolutely anchored — chained
          // right-to-left — so Row layout quirks can't hide them. When
          // settings is open, file/folder hide and the cog stays as a toggle.
          Rectangle {
            id: openFolderBtn
            visible: !root.showSettings
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            width: openFolderLabel.width + Style.space(16)
            radius: root.cornerRadius
            color: openFolderMouse.containsMouse
              ? Util.alpha(root.border, 0.35)
              : "transparent"
            border.color: Util.alpha(root.border, 0.4)
            border.width: 1

            Text {
              id: openFolderLabel
              anchors.centerIn: parent
              text: "󰝰"  // mdi-folder-open (U+F0770)
              color: openFolderMouse.containsMouse
                ? root.selectedText
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: openFolderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openFileLocation()
            }
          }

          Rectangle {
            id: openFileBtn
            visible: !root.showSettings
            anchors.right: openFolderBtn.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            width: openFileLabel.width + Style.space(16)
            radius: root.cornerRadius
            color: openFileMouse.containsMouse
              ? Util.alpha(root.border, 0.35)
              : "transparent"
            border.color: Util.alpha(root.border, 0.4)
            border.width: 1

            Text {
              id: openFileLabel
              anchors.centerIn: parent
              text: "󰈔"  // mdi-file-document (U+F0214)
              color: openFileMouse.containsMouse
                ? root.selectedText
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: openFileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openFile()
            }
          }

          // Cog — toggles the settings pane. Anchors to the right when
          // settings is open (file/folder are hidden), otherwise to their left.
          Rectangle {
            id: settingsBtn
            anchors.right: root.showSettings ? parent.right : openFileBtn.left
            anchors.rightMargin: root.showSettings ? 0 : Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            width: settingsLabel.width + Style.space(16)
            radius: root.cornerRadius
            color: settingsMouse.containsMouse || root.showSettings
              ? Util.alpha(root.border, 0.35)
              : "transparent"
            border.color: Util.alpha(root.border, 0.4)
            border.width: 1

            Text {
              id: settingsLabel
              anchors.centerIn: parent
              text: "󰒓"  // mdi-cog (U+F0493)
              color: settingsMouse.containsMouse || root.showSettings
                ? root.selectedText
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleSettings()
            }
          }

          // Toast slides in to the left of the button group.
          Text {
            text: root.toastMessage
            color: root.foreground
            opacity: root.toastMessage.length > 0 ? 0.7 : 0
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: settingsBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            Behavior on opacity {
              NumberAnimation { duration: 200 }
            }
          }
        }

        // Content area — either the two panes (notes) or the settings form.
        Item {
          id: contentArea
          width: parent.width
          height: parent.height - Style.space(28) - root.contentSpacing

          // Notes view: text + sketch split.
          Item {
            id: notesView
            anchors.fill: parent
            visible: !root.showSettings

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

          // Settings view. Loaded on demand and kept alive after that so
          // reopening is instant. Explicit width/height so the loaded item
          // gets sized reliably.
          Loader {
            id: settingsView
            width: contentArea.width
            height: contentArea.height
            visible: root.showSettings
            active: root.showSettings || item !== null
            source: Qt.resolvedUrl("SettingsPane.qml")
            onLoaded: item.host = root
          }
        }
      }
    }
  }
}
