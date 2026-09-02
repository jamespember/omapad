import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var host: null
  property bool loaded: false

  function focusEditor() {
    textEdit.forceActiveFocus()
    textEdit.cursorPosition = textEdit.length
  }

  function flush() {
    if (saveTimer.running) {
      saveTimer.stop()
      commit()
    }
  }

  function commit() {
    if (!root.host) return
    noteFile.setText(textEdit.text)
    root.host.textContent = textEdit.text
  }

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: root.commit()
  }

  FileView {
    id: noteFile
    path: root.host ? root.host.notePath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var content = text()
      root.loaded = true
      if (textEdit.text !== content) {
        var cursor = textEdit.cursorPosition
        textEdit.text = content
        textEdit.cursorPosition = Math.min(cursor, content.length)
        if (root.host) root.host.textContent = content
      }
    }
    onFileChanged: {
      // Skip while the user has unsaved edits — otherwise we'd clobber them
      // when saveTimer next fires. Our own writes are safe: the reload sees
      // identical text and no-ops via the onLoaded diff check above.
      if (saveTimer.running) return
      reload()
    }
    onLoadFailed: {
      root.loaded = true
      if (textEdit.text.length > 0) return
      textEdit.text = ""
      if (root.host) root.host.textContent = ""
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm

    Item {
      width: parent.width
      height: Style.space(26)

      Text {
        text: "Text"
        color: root.host ? root.host.foreground : "white"
        opacity: 0.6
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        id: copyBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(22)
        width: copyLabel.width + Style.space(16)
        radius: root.host ? root.host.cornerRadius : 4
        color: copyMouse.containsMouse
          ? (root.host ? root.host.selectedBackground : "#444")
          : "transparent"
        border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#555"
        border.width: 1

        Text {
          id: copyLabel
          anchors.centerIn: parent
          text: "copy"
          color: copyMouse.containsMouse
            ? (root.host ? root.host.selectedText : "white")
            : (root.host ? root.host.foreground : "white")
          font.family: root.host ? root.host.fontFamily : ""
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: copyMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.flush()
            if (root.host) root.host.copyText()
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: parent.height - Style.space(26) - Style.spacing.sm
      color: root.host ? Util.alpha(root.host.foreground, 0.03) : "#111"
      radius: root.host ? root.host.cornerRadius : 6
      border.color: root.host ? Util.alpha(root.host.border, 0.3) : "#333"
      border.width: 1

      Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: Style.space(10)
        contentWidth: width
        contentHeight: Math.max(height, textEdit.paintedHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
          id: textEdit
          width: parent.width
          wrapMode: TextEdit.Wrap
          color: root.host ? root.host.foreground : "white"
          selectionColor: root.host ? root.host.selectedBackground : "#444"
          selectedTextColor: root.host ? root.host.selectedText : "white"
          font.family: root.host ? root.host.fontFamily : ""
          font.pixelSize: Style.font.body
          selectByMouse: true
          activeFocusOnPress: true
          persistentSelection: true
          textFormat: TextEdit.PlainText

          onTextChanged: {
            if (!root.loaded) return
            if (root.host) root.host.textContent = text
            saveTimer.restart()
          }

          onCursorRectangleChanged: {
            var top = cursorRectangle.y
            var bottom = cursorRectangle.y + cursorRectangle.height
            if (bottom > scroll.contentY + scroll.height)
              scroll.contentY = bottom - scroll.height
            else if (top < scroll.contentY)
              scroll.contentY = top
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            var ctrlShift = (Qt.ControlModifier | Qt.ShiftModifier)
            if ((event.modifiers & ctrlShift) === ctrlShift) {
              if (event.key === Qt.Key_C) {
                root.flush()
                if (root.host) root.host.copyText()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_S) {
                if (root.host) root.host.copySketch()
                event.accepted = true
                return
              }
            }
            if (event.key === Qt.Key_Escape) {
              if (root.host) root.host.close()
              event.accepted = true
              return
            }
          }
        }
      }
    }
  }
}
