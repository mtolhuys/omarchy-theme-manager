import Quickshell.Io
import QtQuick
import "ThemeCollectionsModel.js" as ThemeCollectionsModel
import "ThemeManagerModel.js" as ThemeManagerModel
import "ImagePickerModel.js" as ImagePickerModel

Item {
  id: root

  property string statePath: ""
  property bool pickerOpen: false
  // The installed-theme rows are on screen (not catalog, wallpapers, or icons).
  property bool active: false
  property var images: []
  property var textMatchingIndices: []
  property string filterText: ""
  property var stockThemes: ({})
  property bool inventoryReady: false
  property string currentThemeName: ""
  property string selectedThemeName: ""
  property int selectedIndex: 0
  property real gridWidth: 0
  property real gridHeight: 0
  property int poolSize: 17

  property var collectionsState: ThemeCollectionsModel.emptyState()
  property bool stateLoaded: false
  // The layout is remembered in the state file; favorites-only resets per open.
  property bool gridMode: false
  // Set once the user switches layout, so a late file load cannot undo it.
  property bool viewTouched: false
  property bool favoritesOnly: false
  property int gridCursor: -1
  property real scrollTop: 0
  property string cursorSectionId: ""

  readonly property var matchingIndices: {
    if (!active) return textMatchingIndices
    const searched = ThemeCollectionsModel.searchIndices(
      images,
      textMatchingIndices,
      filterText,
      collectionsState,
      ImagePickerModel.textMatches)
    return favoritesOnly
      ? ThemeCollectionsModel.favoriteIndices(images, searched, collectionsState)
      : searched
  }
  readonly property var sections: active
    ? ThemeCollectionsModel.sections(images, matchingIndices, collectionsState, {
        stockThemes: stockThemes,
        inventoryReady: inventoryReady,
        favoritesOnly: favoritesOnly
      })
    : []
  readonly property var geometry: ThemeCollectionsModel.gridGeometry(gridWidth, gridHeight)
  readonly property var gridModel: ThemeCollectionsModel.gridModel(sections, geometry)
  readonly property bool gridActive: active && gridMode
  readonly property var gridSlots: gridActive
    ? ThemeCollectionsModel.gridSlots(gridModel, scrollTop, geometry.viewportHeight, poolSize)
    : []
  readonly property var gridHeaders: gridActive
    ? ThemeCollectionsModel.gridHeaders(gridModel, scrollTop, geometry.viewportHeight)
    : []
  readonly property int gridCellCount: gridModel.cells.length
  readonly property string selectedCollectionId: gridActive
    ? ThemeCollectionsModel.sectionIdForPosition(gridModel, gridCursor)
    : ""
  readonly property var selectedCollection: ThemeCollectionsModel.collectionById(
    collectionsState,
    selectedCollectionId)
  readonly property bool canRename: !!selectedCollection
  readonly property bool selectedFavorite: ThemeCollectionsModel.isFavorite(collectionsState, selectedThemeName)
  readonly property int favoriteCount: ThemeCollectionsModel.favoriteCount(collectionsState)
  readonly property int collectionCount: collectionsState.collections.length
  readonly property string backupFileName: "theme-collections.json.bak"
  readonly property string deleteHint: {
    if (selectedCollectionId === "favorites") return "Delete unstars"
    if (selectedCollection) return "Delete removes from " + selectedCollection.name
    return "Delete uninstalls"
  }
  readonly property string hint: {
    if (!active) return ""
    if (gridActive && gridCellCount === 0)
      return favoritesOnly ? "No starred themes match" : "No themes match"
    if (gridActive)
      return "Ctrl+D star  ·  Ctrl+M collections  ·  Ctrl+Shift+N new  ·  "
        + (selectedCollection ? "Ctrl+R rename  ·  " : "")
        + deleteHint
    if (favoritesOnly) return "★ Starred themes only  ·  Ctrl+Shift+D shows all"
    return ""
  }

  signal selectionRequested(int imageIndex)
  signal statusMessage(string message)
  signal focusRequested()

  onPickerOpenChanged: if (!pickerOpen) favoritesOnly = false
  // Handlers hang off the derived properties so they always see settled values.
  onGridActiveChanged: reconcileCursor()
  onGridModelChanged: reconcileCursor()
  onSelectedIndexChanged: followSelection()

  function themeLabel(themeName) {
    return ThemeManagerModel.labelForThemeName(themeName)
  }

  function isFavoriteImage(image) {
    return ThemeCollectionsModel.isFavorite(collectionsState, ThemeCollectionsModel.themeIdForImage(image))
  }

  function isCurrentImage(image) {
    const id = ThemeCollectionsModel.themeIdForImage(image)
    return !!id && id === String(currentThemeName || "").trim()
  }

  function gridCell(slot) {
    return slot >= 0 && slot < gridSlots.length ? gridSlots[slot] : null
  }

  function acceptStateText(raw) {
    const result = ThemeCollectionsModel.parseStateResult(raw)
    if (result.corrupt) {
      backupFile.setText(String(raw || ""))
      statusMessage("Theme collections were unreadable · copy kept as " + backupFileName)
    }
    collectionsState = result.state
    stateLoaded = true
    if (!viewTouched) gridMode = ThemeCollectionsModel.isGridView(collectionsState)
  }

  function save() {
    stateFile.setText(ThemeCollectionsModel.serializeState(collectionsState))
  }

  function ready() {
    if (!active) return false
    if (!stateLoaded) {
      statusMessage("Theme collections are still loading")
      return false
    }
    return true
  }

  function selectedThemeId() {
    return ThemeCollectionsModel.safeThemeId(selectedThemeName)
  }

  // Emits after bindings settle so the picker's match positions are current.
  function emitSelection() {
    const cell = ThemeCollectionsModel.cellAt(gridModel, gridCursor)
    if (cell && cell.imageIndex !== selectedIndex) selectionRequested(cell.imageIndex)
  }

  function setCursor(position) {
    gridCursor = position
    scrollTop = ThemeCollectionsModel.scrollTopForCursor(
      gridModel,
      position,
      geometry.viewportHeight,
      scrollTop)
    const cell = ThemeCollectionsModel.cellAt(gridModel, position)
    if (!cell) return
    cursorSectionId = cell.sectionId
    if (cell.imageIndex !== selectedIndex) Qt.callLater(emitSelection)
  }

  function reconcileCursor() {
    if (!gridActive) {
      gridCursor = -1
      scrollTop = 0
      return
    }
    const count = gridModel.cells.length
    let position = ThemeCollectionsModel.cellPositionForImage(
      gridModel,
      selectedIndex,
      cursorSectionId)
    if (position < 0 && count > 0) position = Math.min(Math.max(0, gridCursor), count - 1)
    setCursor(position)
  }

  function followSelection() {
    if (!gridActive) return
    const position = ThemeCollectionsModel.cellPositionForImage(
      gridModel,
      selectedIndex,
      cursorSectionId)
    setCursor(position >= 0 ? position : gridCursor)
  }

  function toggleGrid() {
    if (!active) return
    gridMode = !gridMode
    viewTouched = true
    // Remembered across restarts. A file that has not loaded yet is left
    // alone rather than overwritten with a state this session never read.
    if (stateLoaded) {
      collectionsState = ThemeCollectionsModel.setView(
        collectionsState,
        gridMode ? "grid" : "carousel")
      save()
    }
    focusRequested()
  }

  function moveGrid(dx, dy) {
    if (!gridActive || gridModel.cells.length === 0) return
    setCursor(ThemeCollectionsModel.moveCursor(gridModel, gridCursor, dx, dy))
  }

  function selectGridPosition(position) {
    if (!gridActive) return
    const cell = ThemeCollectionsModel.cellAt(gridModel, position)
    if (cell) setCursor(cell.position)
    focusRequested()
  }

  function toggleFavorite() {
    const id = selectedThemeId()
    if (!ready() || !id) return
    collectionsState = ThemeCollectionsModel.toggleFavorite(collectionsState, id)
    save()
    const starred = ThemeCollectionsModel.isFavorite(collectionsState, id)
    if (favoritesOnly && ThemeCollectionsModel.favoriteCount(collectionsState) === 0) favoritesOnly = false
    statusMessage((starred ? "★ Starred " : "☆ Unstarred ") + themeLabel(id))
    focusRequested()
  }

  function toggleFavoritesOnly() {
    if (!active) return
    if (favoriteCount === 0) {
      statusMessage("No starred themes yet · Ctrl+D stars the highlighted theme")
      return
    }
    favoritesOnly = !favoritesOnly
    focusRequested()
  }

  // Delete inside Favorites or a collection edits that list; anything else
  // keeps the picker's uninstall meaning (the caller falls through).
  function removeSelectedFromCollection() {
    const id = selectedThemeId()
    if (!gridActive || !ready() || !id) return false
    if (selectedCollectionId === "favorites") {
      if (!ThemeCollectionsModel.isFavorite(collectionsState, id)) return false
      toggleFavorite()
      return true
    }
    const collection = selectedCollection
    if (!collection) return false
    collectionsState = ThemeCollectionsModel.setMembership(collectionsState, collection.id, id, false)
    save()
    statusMessage("Removed " + themeLabel(id) + " from " + collection.name)
    focusRequested()
    return true
  }

  function membershipRows() {
    return ThemeCollectionsModel.membershipRows(collectionsState, selectedThemeId())
  }

  function applyMemberships(rows) {
    const id = selectedThemeId()
    if (!ready() || !id) return
    collectionsState = ThemeCollectionsModel.applyMemberships(collectionsState, id, rows)
    save()
    if (favoritesOnly && ThemeCollectionsModel.favoriteCount(collectionsState) === 0) favoritesOnly = false
    statusMessage("Collections updated for " + themeLabel(id))
    focusRequested()
  }

  function createCollection(name) {
    const id = selectedThemeId()
    if (!ready() || !id) return "Highlight a theme first"
    const result = ThemeCollectionsModel.createCollection(collectionsState, name, [id])
    if (result.error) return result.error
    cursorSectionId = result.id
    collectionsState = result.state
    save()
    statusMessage("Created " + ThemeCollectionsModel.normalizeName(name) + " with " + themeLabel(id))
    focusRequested()
    return ""
  }

  function renameSelectedCollection(name) {
    const collection = selectedCollection
    if (!ready() || !collection) return "Select a collection in the grid first"
    const result = ThemeCollectionsModel.renameCollection(collectionsState, collection.id, name)
    if (result.error) return result.error
    collectionsState = result.state
    save()
    statusMessage("Renamed to " + ThemeCollectionsModel.normalizeName(name))
    focusRequested()
    return ""
  }

  function deleteSelectedCollection() {
    const collection = selectedCollection
    if (!ready() || !collection) return
    collectionsState = ThemeCollectionsModel.deleteCollection(collectionsState, collection.id)
    save()
    statusMessage("Deleted collection " + collection.name)
    focusRequested()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.acceptStateText(text())
    onLoadFailed: root.acceptStateText("")
  }

  // Receives the unreadable original before it is replaced; never read back.
  FileView {
    id: backupFile
    path: ThemeCollectionsModel.backupPath(root.statePath)
    preload: false
    atomicWrites: true
    printErrors: false
  }
}
