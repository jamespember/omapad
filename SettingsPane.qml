import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

// SettingsPane — inline form that edits the plugin's entry in shell.json.
// Replaces the notes area while root.showSettings is true.
Item {
  id: root
  // Fill whatever Loader/parent placed us into. Without this, children with
  // `parent.right`/`parent.bottom` anchors resolve to zero and render nothing.
  anchors.fill: parent

  property var host: null

  // Local editor state. Committed to shell.json on Save; discarded on Cancel.
  property string draftNotePath: ""
  property string draftOpenCommand: ""

  // Preset argvs used by the quick-select chips. Omawrite first — it's the
  // Omarchy Quattro default Markdown editor and works out of the box.
  readonly property var presets: [
    { label: "Omawrite", value: ["omawrite", "{path}"] },
    { label: "Obsidian", value: ["xdg-open", "obsidian://open?path={pathUri}"] },
    { label: "Typora", value: ["typora", "{path}"] },
    { label: "VS Code", value: ["code", "{path}"] },
    { label: "Neovim", value: ["kitty", "nvim", "{path}"] },
    { label: "System", value: ["xdg-open", "{path}"] }
  ]

  // Hydrate the draft fields from the current host state. Assigns both the
  // draft property AND the TextInput.text directly because user typing breaks
  // the property binding — a re-hydrate on reopen must forcibly restore.
  function hydrate() {
    if (!host) return
    // Prefer the raw user-configured value over the resolved absolute path
    // so the ~ stays as ~ in the editor.
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
    draftOpenCommand = Storage.shellJoin(preset.value)
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

  // Hydrate when the host is first wired up (via Loader.onLoaded) and again
  // every time the settings pane is toggled back on, so external edits to
  // shell.json are reflected.
  onHostChanged: if (host) hydrate()

  Connections {
    target: root.host
    enabled: root.host !== null
    function onShowSettingsChanged() {
      if (root.host && root.host.showSettings) root.hydrate()
    }
  }

  // Form fields, top-anchored so they don't fight with the actions row.
  Column {
    id: form
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.md

    // Note path -------------------------------------------------------------
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
          text: root.draftNotePath
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

    // Open command ----------------------------------------------------------
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

      // Preset chips row
      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.presets
          delegate: Rectangle {
            required property var modelData
            id: chip
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
              text: chip.modelData.label
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
              onClicked: root.applyPreset(chip.modelData)
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
          text: root.draftOpenCommand
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

  // Actions row, always bottom-right regardless of the form's content height.
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
