import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

Item {
  id: root

  property var host: null
  property bool loaded: false

  property var currentStroke: null
  property bool drawing: false

  function flush() {
    if (saveTimer.running) {
      saveTimer.stop()
      commit()
    }
  }

  function commit() {
    if (!root.host) return
    sketchFile.setText(Storage.serializeStrokes(root.host.strokes))
  }

  function scheduleSave() {
    saveTimer.restart()
  }

  function undo() {
    if (!root.host || !Array.isArray(root.host.strokes) || root.host.strokes.length === 0) return
    root.host.strokes = root.host.strokes.slice(0, root.host.strokes.length - 1)
    root.scheduleSave()
    canvas.requestPaint()
  }

  function clearAll() {
    if (!root.host) return
    if (root.host.strokes.length === 0) {
      root.host.toast("Sketch is empty")
      return
    }
    root.host.strokes = []
    root.scheduleSave()
    canvas.requestPaint()
    root.host.toast("Sketch cleared")
  }

  function copyAsPng() {
    if (!root.host) return
    if (!Array.isArray(root.host.strokes) || root.host.strokes.length === 0) {
      root.host.toast("Sketch is empty")
      return
    }
    canvas.grabToImage(function(result) {
      var path = root.host.copySketchTmpPath
      result.saveToFile(path)
      Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < '" + path + "'"])
      root.host.toast("Sketch copied")
    })
  }

  Timer {
    id: saveTimer
    interval: 300
    repeat: false
    onTriggered: root.commit()
  }

  FileView {
    id: sketchFile
    path: root.host ? root.host.sketchPath : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loaded = true
      if (root.host) {
        root.host.strokes = Storage.normalizeStrokes(text())
        canvas.requestPaint()
      }
    }
    onLoadFailed: {
      root.loaded = true
      if (root.host && root.host.strokes.length === 0) {
        canvas.requestPaint()
      }
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
        text: "Sketch"
        color: root.host ? root.host.foreground : "white"
        opacity: 0.6
        font.family: root.host ? root.host.fontFamily : ""
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Rectangle {
          height: Style.space(22)
          width: clearLabel.width + Style.space(14)
          radius: root.host ? root.host.cornerRadius : 4
          color: clearMouse.containsMouse
            ? (root.host ? Util.alpha(root.host.border, 0.3) : "#333")
            : "transparent"
          border.color: root.host ? Util.alpha(root.host.border, 0.4) : "#555"
          border.width: 1

          Text {
            id: clearLabel
            anchors.centerIn: parent
            text: "clear"
            color: root.host ? root.host.foreground : "white"
            font.family: root.host ? root.host.fontFamily : ""
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: clearMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }
        }

        Rectangle {
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
            onClicked: root.copyAsPng()
          }
        }
      }
    }

    Rectangle {
      id: canvasFrame
      width: parent.width
      height: parent.height - Style.space(26) - Style.spacing.sm
      color: root.host ? Util.alpha(root.host.foreground, 0.03) : "#111"
      radius: root.host ? root.host.cornerRadius : 6
      border.color: root.host ? Util.alpha(root.host.border, 0.3) : "#333"
      border.width: 1
      clip: true

      Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        renderStrategy: Canvas.Cooperative
        antialiasing: true

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          if (!root.host) return

          ctx.strokeStyle = root.host.foreground
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          ctx.lineJoin = "round"

          var strokes = root.host.strokes || []
          for (var i = 0; i < strokes.length; i++) drawStroke(ctx, strokes[i])
          if (root.currentStroke && root.currentStroke.length > 0)
            drawStroke(ctx, root.currentStroke)
        }

        function drawStroke(ctx, stroke) {
          if (!stroke || stroke.length === 0) return
          ctx.beginPath()
          ctx.moveTo(stroke[0][0], stroke[0][1])
          if (stroke.length === 1) {
            ctx.lineTo(stroke[0][0] + 0.5, stroke[0][1] + 0.5)
          } else {
            for (var i = 1; i < stroke.length; i++)
              ctx.lineTo(stroke[i][0], stroke[i][1])
          }
          ctx.stroke()
        }

        MouseArea {
          id: drawArea
          anchors.fill: parent
          cursorShape: Qt.CrossCursor
          focus: false

          onPressed: function(mouse) {
            root.currentStroke = [[mouse.x, mouse.y]]
            root.drawing = true
            root.forceActiveFocus()
            canvas.requestPaint()
          }

          onPositionChanged: function(mouse) {
            if (!root.drawing) return
            var s = root.currentStroke
            s.push([mouse.x, mouse.y])
            root.currentStroke = s
            canvas.requestPaint()
          }

          onReleased: function(mouse) {
            if (!root.drawing) return
            root.drawing = false
            if (root.currentStroke && root.currentStroke.length >= 2 && root.host) {
              var next = root.host.strokes.slice()
              next.push(root.currentStroke)
              root.host.strokes = next
              root.scheduleSave()
            }
            root.currentStroke = null
            canvas.requestPaint()
          }
        }
      }
    }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
      root.undo()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      if (root.host) root.host.close()
      event.accepted = true
      return
    }
    var ctrlShift = (Qt.ControlModifier | Qt.ShiftModifier)
    if ((event.modifiers & ctrlShift) === ctrlShift) {
      if (event.key === Qt.Key_C) {
        if (root.host) root.host.copyText()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_S) {
        root.copyAsPng()
        event.accepted = true
        return
      }
    }
  }
}
