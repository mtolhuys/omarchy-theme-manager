import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root

  property string summary: "Abstract  ·  Featured  ·  Any open license"
  property bool filtersActive: false
  property int activeCount: 0
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal openRequested()

  spacing: Style.space(10)

  Button {
    id: filtersChip
    anchors.verticalCenter: parent.verticalCenter
    text: root.filtersActive && root.activeCount > 0
      ? ("Filters · " + root.activeCount)
      : "Filters"
    tooltipText: root.filtersActive
      ? ("Active filters: " + root.summary)
      : "Open filters (Ctrl+F)"
    selected: root.filtersActive
    foreground: root.filtersActive ? root.accent : root.foreground
    accent: root.accent
    bordered: true
    horizontalPadding: Style.space(12)
    verticalPadding: Style.space(6)
    onClicked: root.openRequested()
  }

  Rectangle {
    visible: root.filtersActive
    anchors.verticalCenter: parent.verticalCenter
    width: badgeText.implicitWidth + Style.space(10)
    height: Math.max(Style.space(18), badgeText.implicitHeight + Style.space(4))
    radius: height / 2
    color: Util.alpha(root.accent, 0.22)
    border.color: root.accent
    border.width: 1

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.activeCount > 0 ? (root.activeCount + " active") : "Active"
      color: root.accent
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      textFormat: Text.PlainText
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.summary
    color: root.filtersActive ? root.accent : root.foreground
    opacity: root.filtersActive ? 0.95 : 0.78
    font.pixelSize: Style.font.bodySmall
    font.weight: root.filtersActive ? Font.DemiBold : Font.Normal
    textFormat: Text.PlainText
  }
}
