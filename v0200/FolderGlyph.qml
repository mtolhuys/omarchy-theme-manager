import QtQuick
import qs.Commons

// A folder drawn rather than typed. The picker's cards have to read the same
// on every theme, and an icon font that happens to miss one codepoint would
// leave a blank tile where the whole card is the affordance.
Item {
  id: root

  // "folder" carries images, "empty" does not, "up" is the step back out.
  property string kind: "folder"
  property color accent: Color.accent
  property color foreground: Color.foreground
  property real size: Style.space(44)

  readonly property bool isUp: kind === "up"
  readonly property bool isFilled: kind === "folder"

  implicitWidth: size
  implicitHeight: isUp ? size : size * 0.78
  width: implicitWidth
  height: implicitHeight

  // The step out: an outlined disc with the one arrow every font carries.
  Rectangle {
    anchors.fill: parent
    visible: root.isUp
    radius: width / 2
    color: Util.alpha(root.accent, 0.16)
    border.width: Math.max(1, root.size * 0.045)
    border.color: root.accent

    Text {
      anchors.centerIn: parent
      text: "↑"
      color: root.accent
      font.pixelSize: root.size * 0.52
      font.weight: Font.Bold
      textFormat: Text.PlainText
    }
  }

  Item {
    anchors.fill: parent
    visible: !root.isUp

    // The tab, then the body over it, so their seam never shows.
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      width: parent.width * 0.46
      height: parent.height * 0.28
      radius: Math.max(2, root.size * 0.07)
      color: root.isFilled ? root.accent : "transparent"
      opacity: root.isFilled ? 0.85 : 1
      border.width: root.isFilled ? 0 : Math.max(1, root.size * 0.04)
      border.color: Util.alpha(root.foreground, 0.55)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: parent.height * 0.82
      radius: Math.max(2, root.size * 0.09)
      color: root.isFilled ? root.accent : "transparent"
      border.width: root.isFilled ? 0 : Math.max(1, root.size * 0.04)
      border.color: Util.alpha(root.foreground, 0.55)

      // A folder that holds wallpapers says so with a sheet peeking out.
      Rectangle {
        visible: root.isFilled
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.18
        width: parent.width * 0.58
        height: parent.height * 0.34
        radius: Math.max(1, root.size * 0.05)
        color: Util.alpha(root.foreground, 0.75)
      }
    }
  }
}
