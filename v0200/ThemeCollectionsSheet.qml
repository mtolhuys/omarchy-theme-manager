pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "ThemeCollectionsModel.js" as ThemeCollectionsModel

Item {
  id: root

  property bool opened: false
  // "memberships" | "create" | "rename"
  property string mode: ""
  property string themeLabel: ""
  property string collectionName: ""
  property string excludeId: ""
  property var collectionsState: ThemeCollectionsModel.emptyState()
  property var draftRows: []
  property int rowCursor: 0
  property string draftName: ""
  property bool confirmingDelete: false
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.82)
  property color accent: Color.accent

  readonly property bool nameMode: mode === "create" || mode === "rename"
  readonly property string nameError: nameMode
    ? ThemeCollectionsModel.validateCollectionName(collectionsState, draftName, excludeId)
    : ""
  readonly property string title: {
    if (mode === "memberships") return "Collections for " + themeLabel
    if (mode === "create") return "New collection"
    if (confirmingDelete) return "Delete " + collectionName + "?"
    return "Rename " + collectionName
  }
  readonly property string subtitle: {
    if (mode === "memberships") return "Space toggles a collection  ·  Enter saves"
    if (mode === "create") return themeLabel + " becomes its first member"
    if (confirmingDelete) return "Themes stay installed; only the collection goes"
    return "Type a new name  ·  Delete removes the collection"
  }
  readonly property string hint: {
    if (mode === "memberships")
      return draftRows.length > 1
        ? "↑↓ move  ·  Space toggle  ·  Enter save  ·  Escape cancel"
        : "No collections yet  ·  Ctrl+Shift+N creates one"
    if (confirmingDelete) return "Enter delete  ·  Escape keep"
    return "Backspace edit  ·  Ctrl+U clear  ·  Enter save  ·  Escape cancel"
  }

  signal canceled()
  signal membershipsApplied(var rows)
  signal created(string name)
  signal renamed(string name)
  signal deleteConfirmed()

  function openMemberships(label, rows) {
    mode = "memberships"
    themeLabel = String(label || "")
    draftRows = Array.isArray(rows) ? rows.map(function(row) {
      return { id: row.id, name: row.name, member: row.member === true }
    }) : []
    rowCursor = 0
    confirmingDelete = false
    opened = true
  }

  function openCreate(label) {
    mode = "create"
    themeLabel = String(label || "")
    excludeId = ""
    draftName = ""
    confirmingDelete = false
    opened = true
  }

  function openRename(id, name) {
    mode = "rename"
    excludeId = String(id || "")
    collectionName = String(name || "")
    draftName = collectionName
    confirmingDelete = false
    opened = true
  }

  function cancel() {
    opened = false
    confirmingDelete = false
    canceled()
  }

  function toggleRow(index) {
    if (index < 0 || index >= draftRows.length) return
    const next = draftRows.slice()
    next[index] = { id: next[index].id, name: next[index].name, member: !next[index].member }
    draftRows = next
    rowCursor = index
  }

  function apply() {
    if (mode === "memberships") {
      opened = false
      membershipsApplied(draftRows)
      return
    }
    if (confirmingDelete) {
      opened = false
      confirmingDelete = false
      deleteConfirmed()
      return
    }
    if (nameError) return
    const name = ThemeCollectionsModel.normalizeName(draftName)
    opened = false
    if (mode === "create") created(name)
    else renamed(name)
  }

  function isPrintable(event) {
    return !!event.text
      && event.text.length === 1
      && event.text.charCodeAt(0) >= 32
      && event.text.charCodeAt(0) !== 127
      && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
  }

  function appendName(text) {
    if (draftName.length < ThemeCollectionsModel.maxNameLength) draftName += text
  }

  function editName(event) {
    if (Util.editsFilter(event, draftName)) draftName = Util.editedFilter(event, draftName)
    else if (isPrintable(event)) appendName(event.text)
    else return false
    return true
  }

  function handleNameKey(event) {
    // While confirming a delete only Enter and Escape act; both are routed above.
    if (confirmingDelete) return true
    if (mode === "rename" && event.key === Qt.Key_Delete) {
      confirmingDelete = true
      return true
    }
    return editName(event)
  }

  function handleMembershipKey(event) {
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
      rowCursor = Math.max(0, rowCursor - 1)
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
      rowCursor = Math.min(draftRows.length - 1, rowCursor + 1)
    } else if (event.key === Qt.Key_Space) {
      toggleRow(rowCursor)
    } else {
      return false
    }
    return true
  }

  function handleEscape() {
    if (confirmingDelete) confirmingDelete = false
    else cancel()
    return true
  }

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) return handleEscape()
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      apply()
      return true
    }
    return mode === "memberships" ? handleMembershipKey(event) : handleNameKey(event)
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

    width: Math.min(parent.width - Style.space(48), Style.space(520))
    height: Style.space(root.mode === "memberships" ? 420 : 250)
    anchors.centerIn: parent
    color: root.background
    borderSpec: Border.flat(root.confirmingDelete ? Color.urgent : root.accent, Style.normalBorderWidth)
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
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.title
          color: root.confirmingDelete ? Color.urgent : root.foreground
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: root.subtitle
          color: root.foreground
          opacity: 0.64
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      ListView {
        id: membershipList
        visible: root.mode === "memberships"
        width: parent.width
        height: Style.space(232)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Style.space(4)
        model: root.draftRows
        currentIndex: root.rowCursor
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 0
        keyNavigationWraps: false

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: membershipList.width
          height: Style.spacing.popupRowHeight
          radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
          color: index === root.rowCursor
            ? Style.hoverFillFor(root.foreground, root.accent)
            : "transparent"

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.member ? "◉" : "○"
              color: modelData.member ? root.accent : root.foreground
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (modelData.id === "favorites" ? "★ " : "") + String(modelData.name || "")
              color: index === root.rowCursor
                ? Style.hoverStateColor(root.foreground, root.accent)
                : root.foreground
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.rowCursor = parent.index
            onClicked: root.toggleRow(parent.index)
          }
        }
      }

      Item {
        visible: root.nameMode
        width: parent.width
        height: Style.space(62)

        BorderSurface {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.spacing.controlHeight + Style.space(6)
          color: Util.alpha(root.foreground, 0.06)
          borderSpec: Border.flat(root.nameError ? Util.alpha(root.foreground, 0.38) : root.accent, Style.normalBorderWidth)
          radius: Style.cornerRadius

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: root.confirmingDelete ? root.collectionName : root.draftName + "▏"
            color: root.foreground
            font.pixelSize: Style.font.title
            elide: Text.ElideLeft
            textFormat: Text.PlainText
          }
        }

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          visible: !root.confirmingDelete && !!root.draftName && !!root.nameError
          text: root.nameError
          color: Color.urgent
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      Item {
        width: parent.width
        height: Style.space(40)

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          text: root.hint
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
            visible: root.mode === "rename" && !root.confirmingDelete
            text: "Delete collection"
            foreground: Color.urgent
            accent: Color.urgent
            bordered: true
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(7)
            onClicked: root.confirmingDelete = true
          }

          Button {
            text: root.confirmingDelete ? "Keep" : "Cancel"
            foreground: root.foreground
            accent: root.accent
            bordered: true
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(7)
            onClicked: {
              if (root.confirmingDelete) root.confirmingDelete = false
              else root.cancel()
            }
          }

          Button {
            enabled: root.mode === "memberships" || root.confirmingDelete || !root.nameError
            text: root.confirmingDelete
              ? "Delete"
              : (root.mode === "memberships" ? "Save" : (root.mode === "create" ? "Create" : "Rename"))
            selected: true
            foreground: root.confirmingDelete ? Color.urgent : root.foreground
            accent: root.confirmingDelete ? Color.urgent : root.accent
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
