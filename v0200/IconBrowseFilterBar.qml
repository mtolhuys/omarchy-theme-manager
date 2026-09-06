import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root

  property string summary: "Newest"
  property bool filtersActive: false
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal openRequested()

  spacing: Style.space(10)

  Button {
    anchors.verticalCenter: parent.verticalCenter
    text: "Filters"
    tooltipText: "Choose icon catalog sort (Ctrl+F)"
    selected: root.filtersActive
    foreground: root.foreground
    accent: root.accent
    bordered: true
    horizontalPadding: Style.space(12)
    verticalPadding: Style.space(6)
    onClicked: root.openRequested()
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.summary
    color: root.foreground
    opacity: 0.78
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }
}
