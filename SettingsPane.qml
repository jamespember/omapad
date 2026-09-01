import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

Item {
  id: root
  anchors.fill: parent

  property var host: null

  property string draftNotePath: ""
  property string draftOpenCommand: ""

  readonly property var presets: [
    { label: "Omawrite", value: ["uwsm-app", "--", "omawrite", "{path}"] },
    { label: "Obsidian", value: ["xdg-open", "obsidian://open?path={pathUri}"] },
    { label: "VS Code", value: ["uwsm-app", "--", "code", "{path}"] },
    { label: "Neovim", value: ["uwsm-app", "--", "xdg-terminal-exec", "--", "nvim", "{path}"] },
    { label: "System", value: ["xdg-open", "{path}"] }
  ]

  function hydrate() {
    if (!host) return
    var nextNotePath = host.rawNotePath || host.notePath || ""
    var cmd = Array.isArray(host.openCommand) ? host.openCommand : host.defaultOpenCommand
    var nextOpenCommand = Storage.shellJoin(cmd)

    draftNotePath = nextNotePath
    draftOpenCommand = nextOpenCommand
    notePathField.text = nextNotePath
    openCommandField.text = nextOpenCommand

    Qt.callLater(function() { notePathField.forceActiveFocus() })
  }

  function applyPreset(preset) {
    var joined = Storage.shellJoin(preset.value)
    draftOpenCommand = joined
    openCommandField.text = joined
  }

  function save() {
    if (!host) return
    var argv = Storage.shellSplit(draftOpenCommand)
    host.saveSettings({
      notePath: draftNotePath,
      openCommand: argv.length > 0 ? argv : null
    })
    host.showSettings = false
  }

  function cancel() {
    if (host) host.showSettings = false
  }

  onHostChanged: if (host) hydrate()

  Connections {
    target: root.host
    enabled: root.host !== null
    function onShowSettingsChanged() {
      if (root.host && root.host.showSettings) root.hydrate()
    }
  }

  Column {
    id: form
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.md

    Column {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "Note file path"
        color: root.host ? root.host.foreground : "white"
        opacity: 0.7
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        width: parent.width
        height: Style.space(34)
        color: root.host ? Util.alpha(root.host.foreground, 0.03) : "#111"
        radius: root.host ? root.host.cornerRadius : 6
        border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#333"
        border.width: 1

        TextInput {
          id: notePathField
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          verticalAlignment: TextInput.AlignVCenter
          color: root.host ? root.host.foreground : "white"
          selectionColor: root.host ? root.host.selectedBackground : "#444"
          selectedTextColor: root.host ? root.host.selectedText : "white"
          font.family: root.host ? root.host.fontFamily : ""
          font.pixelSize: Style.font.body
          selectByMouse: true
          activeFocusOnPress: true
          onTextChanged: root.draftNotePath = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.save(); event.accepted = true
            }
          }
        }
      }

      Text {
        text: "Where the text pane persists. ~ and $HOME are expanded."
        color: root.host ? root.host.foreground : "white"
        opacity: 0.45
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "Open-file command"
        color: root.host ? root.host.foreground : "white"
        opacity: 0.7
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.presets.length
          delegate: Rectangle {
            id: chip
            required property int index
            readonly property var preset: root.presets[chip.index]
            height: Style.space(22)
            width: chipLabel.width + Style.space(14)
            radius: root.host ? root.host.cornerRadius : 4
            color: chipMouse.containsMouse
              ? (root.host ? root.host.selectedBackground : "#444")
              : "transparent"
            border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#555"
            border.width: 1

            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: chip.preset ? chip.preset.label : ""
              color: chipMouse.containsMouse
                ? (root.host ? root.host.selectedText : "white")
                : (root.host ? root.host.foreground : "white")
              font.family: root.host ? root.host.fontFamily : ""
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: chipMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (chip.preset) root.applyPreset(chip.preset)
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(34)
        color: root.host ? Util.alpha(root.host.foreground, 0.03) : "#111"
        radius: root.host ? root.host.cornerRadius : 6
        border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#333"
        border.width: 1

        TextInput {
          id: openCommandField
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          verticalAlignment: TextInput.AlignVCenter
          color: root.host ? root.host.foreground : "white"
          selectionColor: root.host ? root.host.selectedBackground : "#444"
          selectedTextColor: root.host ? root.host.selectedText : "white"
          font.family: root.host ? root.host.fontFamily : ""
          font.pixelSize: Style.font.body
          selectByMouse: true
          activeFocusOnPress: true
          onTextChanged: root.draftOpenCommand = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.save(); event.accepted = true
            }
          }
        }
      }

      Text {
        text: "Shell-style command. Use {path} for the file and {pathUri} for a URL-encoded path."
        color: root.host ? root.host.foreground : "white"
        opacity: 0.45
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }

  Row {
    id: actionsRow
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.spacing.md
    anchors.bottomMargin: Style.spacing.md
    spacing: Style.space(8)
    height: Style.space(28)

    Rectangle {
      height: Style.space(28)
      width: cancelLabel.width + Style.space(20)
      radius: root.host ? root.host.cornerRadius : 4
      color: cancelMouse.containsMouse
        ? (root.host ? Util.alpha(root.host.border, 0.35) : "#333")
        : "transparent"
      border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#555"
      border.width: 1

      Text {
        id: cancelLabel
        anchors.centerIn: parent
        text: "Cancel"
        color: root.host ? root.host.foreground : "white"
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: cancelMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.cancel()
      }
    }

    Rectangle {
      height: Style.space(28)
      width: saveLabel.width + Style.space(20)
      radius: root.host ? root.host.cornerRadius : 4
      color: saveMouse.containsMouse
        ? (root.host ? root.host.selectedBackground : "#444")
        : (root.host ? Util.alpha(root.host.selectedBackground, 0.4) : "#333")
      border.color: root.host ? Util.alpha(root.host.border, 0.5) : "#666"
      border.width: 1

      Text {
        id: saveLabel
        anchors.centerIn: parent
        text: "Save"
        color: saveMouse.containsMouse
          ? (root.host ? root.host.selectedText : "white")
          : (root.host ? root.host.foreground : "white")
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      MouseArea {
        id: saveMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.save()
      }
    }
  }
}
