import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool showSettings: false

  property string rawNotePath: "~/.local/state/omapad/note.txt"

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

  property string home: Quickshell.env("HOME")
  property string shellConfigPath: home + "/.config/omarchy/shell.json"
  property string defaultNotePath: home + "/.local/state/omapad/note.txt"
  property string sketchPath: home + "/.local/state/omapad/sketch.json"
  property string notePath: defaultNotePath
  property string copyTextTmpPath: "/tmp/omapad-copy-text.txt"
  property string copySketchTmpPath: "/tmp/omapad-copy-sketch.png"

  readonly property var defaultOpenCommand: ["uwsm-app", "--", "omawrite", "{path}"]
  property var openCommand: defaultOpenCommand

  property string textContent: ""
  property var strokes: []

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

  function open(payloadJson) {
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

  function copyText() {
    if (!root.textContent || root.textContent.length === 0) {
      root.toast("Nothing to copy")
      return
    }
    var encoded
    try {
      encoded = Qt.btoa(new TextEncoder().encode(root.textContent))
    } catch (e) {
      encoded = Qt.btoa(root.textContent)
    }
    Quickshell.execDetached(["sh", "-c", "printf %s " + encoded + " | base64 -d | wl-copy"])
    root.toast("Text copied")
  }

  function copySketch() {
    if (sketchPane.item) sketchPane.item.copyAsPng()
  }

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

  function openFileLocation() {
    Quickshell.execDetached(["xdg-open", Storage.dirname(root.notePath)])
    root.toast("Opening folder")
    root.close()
  }

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

  Process { id: mkdirProc; running: false }
  function ensureDirs() {
    mkdirProc.command = ["mkdir", "-p",
      Storage.dirname(root.notePath),
      Storage.dirname(root.sketchPath)]
    mkdirProc.running = true
  }
  Component.onCompleted: ensureDirs()
  onNotePathChanged: ensureDirs()

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

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

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
              text: "󰝰"
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
              text: "󰈔"
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
              text: "󰒓"
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

        Item {
          id: contentArea
          width: parent.width
          height: parent.height - Style.space(28) - root.contentSpacing

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
