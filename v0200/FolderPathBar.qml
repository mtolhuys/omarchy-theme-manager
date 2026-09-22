import QtQuick
import qs.Commons
import qs.Ui

// The folder browser's breadcrumb: every step of the path back to Home is a
// chip, and every chip is a jump. A deep path keeps its last few steps and
// folds the rest behind one ellipsis chip.
Row {
  id: root

  // [{ name, path }], Home first, as FolderBrowseModel.breadcrumb builds it.
  property var segments: []
  property string summary: ""
  property bool showHidden: false
  property bool busy: false
  property color foreground: Color.foreground
  property color accent: Color.accent

  readonly property int maxVisibleSegments: 4
  readonly property var visibleSegments: {
    const trail = Array.isArray(segments) ? segments : []
    return trail.length > maxVisibleSegments ? trail.slice(-maxVisibleSegments) : trail
  }
  readonly property var foldedSegment: {
    const trail = Array.isArray(segments) ? segments : []
    return trail.length > maxVisibleSegments ? trail[trail.length - maxVisibleSegments - 1] : null
  }

  signal navigateRequested(string path)
  signal hiddenToggleRequested()

  spacing: Style.space(6)

  Button {
    visible: !!root.foldedSegment
    anchors.verticalCenter: parent.verticalCenter
    text: "…"
    tooltipText: root.foldedSegment ? ("Back to " + root.foldedSegment.name) : ""
    foreground: root.foreground
    accent: root.accent
    bordered: true
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(5)
    onClicked: if (root.foldedSegment) root.navigateRequested(String(root.foldedSegment.path))
  }

  Repeater {
    model: root.visibleSegments

    Row {
      required property var modelData
      required property int index

      readonly property bool last: index === root.visibleSegments.length - 1

      spacing: Style.space(6)

      Text {
        visible: index > 0 || !!root.foldedSegment
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: root.foreground
        opacity: 0.55
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: String(modelData.name || "")
        tooltipText: last ? "This folder" : ("Jump to " + String(modelData.name || ""))
        selected: last
        enabled: !last
        foreground: last ? root.accent : root.foreground
        accent: root.accent
        bordered: true
        horizontalPadding: Style.space(10)
        verticalPadding: Style.space(5)
        onClicked: root.navigateRequested(String(modelData.path || ""))
      }
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: !!root.summary
    leftPadding: Style.space(6)
    text: root.busy ? "Reading folder…" : root.summary
    color: root.foreground
    opacity: 0.78
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  Button {
    anchors.verticalCenter: parent.verticalCenter
    text: root.showHidden ? "Hidden shown" : "Hidden"
    tooltipText: root.showHidden
      ? "Stop listing dot-folders and dot-files (Ctrl+H)"
      : "Also list dot-folders and dot-files (Ctrl+H)"
    selected: root.showHidden
    foreground: root.showHidden ? root.accent : root.foreground
    accent: root.accent
    bordered: true
    horizontalPadding: Style.space(10)
    verticalPadding: Style.space(5)
    onClicked: root.hiddenToggleRequested()
  }
}
