pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ThemeCatalogModel.js" as ThemeCatalogModel

Item {
  id: root

  property bool opened: false
  property string draftListing: "all"
  property string draftAvailability: "all"
  property string draftSort: "best"
  property int draftMinStars: 0
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color scrim: Util.alpha(Commons.Color.background, 0.82)
  property color accent: Commons.Color.accent
  property int cursorSection: 0
  property int listingCursor: 0
  property int availabilityCursor: 0
  property int sortCursor: 0
  property int minStarsCursor: 0
  readonly property var listingOptions: ThemeCatalogModel.getListingOptions()
  readonly property var availabilityOptions: ThemeCatalogModel.getAvailabilityOptions()
  readonly property var sortOptions: ThemeCatalogModel.getCatalogSortOptions()
  readonly property var minStarsOptions: ThemeCatalogModel.getMinStarsOptions()

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
    return ThemeCatalogModel.normalizeCatalogFilters({
      listing: draftListing,
      availability: draftAvailability,
      sort: draftSort,
      minStars: draftMinStars
    })
  }

  function openWith(filters) {
    const normalized = ThemeCatalogModel.normalizeCatalogFilters(filters)
    draftListing = normalized.listing
    draftAvailability = normalized.availability
    draftSort = normalized.sort
    draftMinStars = normalized.minStars
    cursorSection = 0
    listingCursor = optionIndex(listingOptions, draftListing, 0)
    availabilityCursor = optionIndex(availabilityOptions, draftAvailability, 0)
    sortCursor = optionIndex(sortOptions, draftSort, 0)
    minStarsCursor = optionIndex(minStarsOptions, draftMinStars, 0)
    opened = true
  }

  function resetDraft() {
    const defaults = ThemeCatalogModel.defaultCatalogFilters()
    draftListing = defaults.listing
    draftAvailability = defaults.availability
    draftSort = defaults.sort
    draftMinStars = defaults.minStars
    listingCursor = 0
    availabilityCursor = 0
    sortCursor = 0
    minStarsCursor = 0
  }

  function cancel() {
    opened = false
    canceled()
  }

  function apply() {
    const filters = draftFilters()
    opened = false
    applied(filters)
  }

  function handleKey(event) {
    if (!opened) return false

    if (event.key === Qt.Key_Escape) {
      cancel()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      apply()
    } else if (event.key === Qt.Key_Backspace) {
      resetDraft()
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
      cursorSection = wrap(cursorSection - 1, 4)
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
      cursorSection = wrap(cursorSection + 1, 4)
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      const direction = event.key === Qt.Key_Left ? -1 : 1
      if (cursorSection === 0) {
        listingCursor = wrap(listingCursor + direction, listingOptions.length)
        draftListing = listingOptions[listingCursor].value
      } else if (cursorSection === 1) {
        availabilityCursor = wrap(availabilityCursor + direction, availabilityOptions.length)
        draftAvailability = availabilityOptions[availabilityCursor].value
      } else if (cursorSection === 2) {
        sortCursor = wrap(sortCursor + direction, sortOptions.length)
        draftSort = sortOptions[sortCursor].value
      } else {
        minStarsCursor = wrap(minStarsCursor + direction, minStarsOptions.length)
        draftMinStars = minStarsOptions[minStarsCursor].value
      }
    } else if (event.key === Qt.Key_Space) {
      if (cursorSection === 0) {
        listingCursor = wrap(listingCursor + 1, listingOptions.length)
        draftListing = listingOptions[listingCursor].value
      } else if (cursorSection === 1) {
        availabilityCursor = wrap(availabilityCursor + 1, availabilityOptions.length)
        draftAvailability = availabilityOptions[availabilityCursor].value
      } else if (cursorSection === 2) {
        sortCursor = wrap(sortCursor + 1, sortOptions.length)
        draftSort = sortOptions[sortCursor].value
      } else {
        minStarsCursor = wrap(minStarsCursor + 1, minStarsOptions.length)
        draftMinStars = minStarsOptions[minStarsCursor].value
      }
    } else {
      return false
    }

    return true
  }

  visible: opened
  z: 500

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }
  }

  BorderSurface {
    id: card

    width: Math.min(parent.width - Style.space(48), Style.space(820))
    height: Style.space(400)
    anchors.centerIn: parent
    color: root.background
    borderSpec: Border.flat(root.accent, Style.normalBorderWidth)
    radius: Style.cornerRadius
    padding: Style.space(24)

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: Style.space(14)

      Item {
        width: parent.width
        height: Style.space(48)

        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          text: "Filter theme catalog"
          color: root.foreground
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          textFormat: Text.PlainText
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          text: "Stage filters locally, then apply to the catalog carousel"
          color: root.foreground
          opacity: 0.64
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }

      Item {
        width: parent.width
        height: Style.space(38)

        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Listing"
          color: root.cursorSection === 0 ? root.accent : root.foreground
          opacity: root.cursorSection === 0 ? 1 : 0.72
          font.pixelSize: Style.font.body
          font.weight: root.cursorSection === 0 ? Font.DemiBold : Font.Normal
          textFormat: Text.PlainText
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(118)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.listingOptions

            Button {
              required property int index
              required property var modelData

              text: modelData.label
              selected: root.draftListing === modelData.value
              hasCursor: root.cursorSection === 0 && root.listingCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 0
                root.listingCursor = index
                root.draftListing = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(38)

        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Availability"
          color: root.cursorSection === 1 ? root.accent : root.foreground
          opacity: root.cursorSection === 1 ? 1 : 0.72
          font.pixelSize: Style.font.body
          font.weight: root.cursorSection === 1 ? Font.DemiBold : Font.Normal
          textFormat: Text.PlainText
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(118)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.availabilityOptions

            Button {
              required property int index
              required property var modelData

              text: modelData.label
              selected: root.draftAvailability === modelData.value
              hasCursor: root.cursorSection === 1 && root.availabilityCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 1
                root.availabilityCursor = index
                root.draftAvailability = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(38)

        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Sort"
          color: root.cursorSection === 2 ? root.accent : root.foreground
          opacity: root.cursorSection === 2 ? 1 : 0.72
          font.pixelSize: Style.font.body
          font.weight: root.cursorSection === 2 ? Font.DemiBold : Font.Normal
          textFormat: Text.PlainText
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(118)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.sortOptions

            Button {
              required property int index
              required property var modelData

              text: modelData.label
              selected: root.draftSort === modelData.value
              hasCursor: root.cursorSection === 2 && root.sortCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 2
                root.sortCursor = index
                root.draftSort = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(38)

        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Min stars"
          color: root.cursorSection === 3 ? root.accent : root.foreground
          opacity: root.cursorSection === 3 ? 1 : 0.72
          font.pixelSize: Style.font.body
          font.weight: root.cursorSection === 3 ? Font.DemiBold : Font.Normal
          textFormat: Text.PlainText
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(118)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.minStarsOptions

            Button {
              required property int index
              required property var modelData

              text: modelData.label
              selected: root.draftMinStars === modelData.value
              hasCursor: root.cursorSection === 3 && root.minStarsCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 3
                root.minStarsCursor = index
                root.draftMinStars = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(72)

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          text: "↑↓ section  ·  ←→ / Space choice  ·  Backspace reset  ·  Enter apply"
          color: root.foreground
          opacity: 0.58
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(8)

          Button {
            text: "Reset"
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(7)
            onClicked: root.resetDraft()
          }

          Button {
            text: "Cancel"
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(7)
            onClicked: root.cancel()
          }

          Button {
            text: "Apply filters"
            selected: true
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(7)
            onClicked: root.apply()
          }
        }
      }
    }
  }
}
