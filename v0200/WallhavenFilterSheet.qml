pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "WallpaperBrowserModel.js" as WallpaperBrowserModel

Item {
  id: root

  property bool opened: false
  property string draftCollection: "omarchy"
  property string draftSorting: "featured"
  property string draftLicense: "any"
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.82)
  property color accent: Color.accent
  property int cursorSection: 0
  property int collectionCursor: 0
  property int sortingCursor: 0
  property int licenseCursor: 0
  readonly property var collectionOptions: WallpaperBrowserModel.getCollectionOptions()
  readonly property var sortingOptions: WallpaperBrowserModel.getSortingOptions()
  readonly property var licenseOptions: WallpaperBrowserModel.getLicenseOptions()
  readonly property bool communityOptionsVisible: draftCollection !== "omarchy"

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
    return WallpaperBrowserModel.normalizeFilters({
      collection: draftCollection,
      sorting: draftSorting,
      license: draftLicense
    })
  }

  function openWith(filters) {
    const normalized = WallpaperBrowserModel.normalizeFilters(filters)
    draftCollection = normalized.collection
    draftSorting = normalized.sorting
    draftLicense = normalized.license
    cursorSection = 0
    collectionCursor = optionIndex(collectionOptions, draftCollection, 0)
    sortingCursor = optionIndex(sortingOptions, draftSorting, 0)
    licenseCursor = optionIndex(licenseOptions, draftLicense, 0)
    opened = true
  }

  function resetDraft() {
    const defaults = WallpaperBrowserModel.defaultFilters()
    draftCollection = defaults.collection
    draftSorting = defaults.sorting
    draftLicense = defaults.license
    collectionCursor = 0
    sortingCursor = 0
    licenseCursor = 0
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
      cursorSection = communityOptionsVisible ? wrap(cursorSection - 1, 3) : 0
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
      cursorSection = communityOptionsVisible ? wrap(cursorSection + 1, 3) : 0
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      const direction = event.key === Qt.Key_Left ? -1 : 1
      if (cursorSection === 0) {
        collectionCursor = wrap(collectionCursor + direction, collectionOptions.length)
        draftCollection = collectionOptions[collectionCursor].value
        if (!communityOptionsVisible) cursorSection = 0
      } else if (cursorSection === 1) {
        sortingCursor = wrap(sortingCursor + direction, sortingOptions.length)
        draftSorting = sortingOptions[sortingCursor].value
      } else if (cursorSection === 2) {
        licenseCursor = wrap(licenseCursor + direction, licenseOptions.length)
        draftLicense = licenseOptions[licenseCursor].value
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
    MouseArea { anchors.fill: parent; onClicked: root.cancel() }
  }

  BorderSurface {
    id: card
    width: Math.min(parent.width - Style.space(48), Style.space(900))
    height: Style.space(root.communityOptionsVisible ? 370 : 270)
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
          text: "Filter open wallpapers"
          color: root.foreground
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          textFormat: Text.PlainText
        }
        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          text: root.communityOptionsVisible
            ? "Unbranded open community art · photography kept separate"
            : "Bundled Omarchy wallpapers · local, cached, no re-download"
          color: root.foreground
          opacity: 0.64
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
        BorderSurface {
          anchors.right: parent.right
          anchors.top: parent.top
          width: sourceText.implicitWidth + Style.space(18)
          height: Style.space(28)
          color: Util.alpha(root.accent, 0.12)
          borderSpec: Border.flat(Util.alpha(root.accent, 0.8), Style.normalBorderWidth)
          radius: Style.cornerRadius
          Text {
            id: sourceText
            anchors.centerIn: parent
            text: "No API key"
            color: root.accent
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
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
          text: "Collection"
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
          spacing: Style.space(6)
          Repeater {
            model: root.collectionOptions
            Button {
              required property int index
              required property var modelData
              text: modelData.label
              selected: root.draftCollection === modelData.value
              hasCursor: root.cursorSection === 0 && root.collectionCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 0
                root.collectionCursor = index
                root.draftCollection = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        visible: root.communityOptionsVisible
        height: visible ? Style.space(38) : 0
        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Sort"
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
            model: root.sortingOptions
            Button {
              required property int index
              required property var modelData
              text: modelData.label
              selected: root.draftSorting === modelData.value
              hasCursor: root.cursorSection === 1 && root.sortingCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 1
                root.sortingCursor = index
                root.draftSorting = modelData.value
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        visible: root.communityOptionsVisible
        height: visible ? Style.space(38) : 0
        Text {
          width: Style.space(108)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "License"
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
          spacing: Style.space(6)
          Repeater {
            model: root.licenseOptions
            Button {
              required property int index
              required property var modelData
              text: modelData.label
              selected: root.draftLicense === modelData.value
              hasCursor: root.cursorSection === 2 && root.licenseCursor === index
              foreground: root.foreground
              accent: root.accent
              bordered: true
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(6)
              onClicked: {
                root.cursorSection = 2
                root.licenseCursor = index
                root.draftLicense = modelData.value
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
          text: "↑↓ section  ·  ←→ choice  ·  Backspace reset  ·  Enter apply"
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
