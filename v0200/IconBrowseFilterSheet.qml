pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "IconBrowseModel.js" as IconBrowseModel

Item {
  id: root

  property bool opened: false
  property string draftSorting: "new"
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.82)
  property color accent: Color.accent
  property int sortingCursor: 0
  readonly property var sortingOptions: IconBrowseModel.getSortingOptions()

  signal canceled()
  signal applied(var filters)

  function optionIndex(options, value, fallback) {
    for (let index = 0; index < options.length; index++) {
      if (String(options[index].value) === String(value)) return index
    }
    return fallback
  }

  function wrap(index, length) {
    return (index + length) % length
  }

  function draftFilters() {
    return IconBrowseModel.normalizeFilters({ sorting: draftSorting })
  }

  function openWith(filters) {
    const normalized = IconBrowseModel.normalizeFilters(filters)
    draftSorting = normalized.sorting
    sortingCursor = optionIndex(sortingOptions, draftSorting, 0)
    opened = true
  }

  function resetDraft() {
    draftSorting = "new"
    sortingCursor = 0
  }

  function closeCanceled() {
    opened = false
    canceled()
  }

  function closeApplied() {
    opened = false
    applied(draftFilters())
  }

  function handleKey(event) {
    if (!opened) return false

    if (event.key === Qt.Key_Escape) {
      closeCanceled()
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      closeApplied()
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      resetDraft()
      return true
    }
    if (event.key === Qt.Key_Left) {
      sortingCursor = wrap(sortingCursor - 1, sortingOptions.length)
      draftSorting = sortingOptions[sortingCursor].value
      return true
    }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Space) {
      sortingCursor = wrap(sortingCursor + 1, sortingOptions.length)
      draftSorting = sortingOptions[sortingCursor].value
      return true
    }
    return true
  }

  visible: opened
  z: 1100

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeCanceled()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), 520)
    height: sheetColumn.implicitHeight + Style.space(36)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(12)
    color: root.background
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.28)

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    Column {
      id: sheetColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(18)
      spacing: Style.space(16)

      Text {
        text: "Icon catalog filters"
        color: root.foreground
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        textFormat: Text.PlainText
      }

      Text {
        text: "Sort"
        color: root.foreground
        opacity: 0.8
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      Flow {
        width: parent.width
        spacing: Style.space(8)

        Repeater {
          model: root.sortingOptions

          Button {
            required property var modelData
            required property int index
            text: modelData.label
            selected: root.draftSorting === modelData.value
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(7)
            onClicked: {
              root.sortingCursor = index
              root.draftSorting = modelData.value
            }
          }
        }
      }

      Text {
        width: parent.width
        text: "←→ / Space cycle  ·  Backspace reset  ·  Enter apply  ·  Esc cancel"
        color: root.foreground
        opacity: 0.65
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
      }

      Row {
        spacing: Style.space(10)
        anchors.right: parent.right

        Button {
          text: "Cancel"
          foreground: root.foreground
          accent: root.accent
          bordered: true
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.closeCanceled()
        }

        Button {
          text: "Apply"
          foreground: root.foreground
          accent: root.accent
          bordered: true
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(7)
          onClicked: root.closeApplied()
        }
      }
    }
  }
}
