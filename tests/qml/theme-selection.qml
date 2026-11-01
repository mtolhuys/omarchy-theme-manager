import QtQuick
import Quickshell
import "runtime"
import "runtime/ImagePickerModel.js" as ImagePickerModel
import "runtime/ThemeManagerModel.js" as ThemeManagerModel

// The picker's selection plumbing around the real ThemeCollectionsController:
// the same bindings, carousel sync and loadRows order as ImagePicker.qml.
// Issue #3: loadRows chose the index before swapping the rows in, and the
// collection bindings settled through intermediate match sets that did not
// hold it, so the sync fell back to the first theme.
ShellRoot {
  id: root
  property var imageArray: []
  property string filterText: ""
  property string selectedImage: ""
  property int selectedIndex: 0
  property int carouselCursor: 0
  readonly property bool themeRowsLoaded: imageArray.length > 0
    && ThemeManagerModel.isThemePreviewPath(imageArray[0].filePath)
  readonly property bool themeCollectionsActive: themeRowsLoaded
  readonly property var textMatchingIndices: ImagePickerModel.matchingIndices(imageArray, filterText)
  readonly property var matchingIndices: themeCollectionsActive
    ? themeCollections.matchingIndices
    : textMatchingIndices
  readonly property var matchingPositions: ImagePickerModel.positionsForIndices(
    matchingIndices,
    imageArray.length)
  readonly property string previews: Quickshell.env("HOME") + "/.cache/omarchy/theme-selector/previews/"

  onMatchingIndicesChanged: syncCarouselCursor()
  onSelectedIndexChanged: syncCarouselCursor()

  ThemeCollectionsController {
    id: themeCollections
    pluginId: "io.github.mtolhuys.theme-manager"
    pickerOpen: true
    active: root.themeCollectionsActive
    images: root.imageArray
    textMatchingIndices: root.textMatchingIndices
    filterText: root.filterText
    selectedIndex: root.selectedIndex
  }

  function filteredPosition(index) {
    return index >= 0 && index < matchingPositions.length
      ? matchingPositions[index]
      : -1
  }

  function syncCarouselCursor() {
    const position = filteredPosition(selectedIndex)
    if (position >= 0) {
      carouselCursor = ImagePickerModel.nearestWrappedCursor(
        carouselCursor,
        position,
        matchingIndices.length)
    } else if (matchingIndices.length > 0) {
      carouselCursor = 0
      selectedIndex = matchingIndices[0]
    } else {
      carouselCursor = 0
    }
  }

  function loadRows(rows) {
    imageArray = ImagePickerModel.loadRows(rows)
    selectedIndex = ImagePickerModel.indexForSelectedImage(imageArray, selectedImage)
  }

  function themeRows(count) {
    const names = ["akane", "catppuccin", "ember", "everforest", "flexoki", "gruvbox",
      "hackerman", "kanagawa", "lumen", "matte", "nord", "osaka"]
    return names.slice(0, count).map(function(name) { return previews + name + ".png" }).join("\n")
  }

  function opensOnCurrent(label, before) {
    imageArray = before
    selectedIndex = 0
    selectedImage = previews + "lumen.png"
    loadRows(themeRows(12))
    const chosen = imageArray[selectedIndex] ? imageArray[selectedIndex].filePath : ""
    if (chosen === selectedImage) return true
    console.log("THEME SELECTION FAIL " + label + " opened on " + chosen)
    return false
  }

  Component.onCompleted: {
    const wallpapers = ImagePickerModel.loadRows(
      ["a", "b", "c"].map(function(name) { return Quickshell.env("HOME") + "/" + name + ".jpg" }).join("\n"))
    const passed = opensOnCurrent("from an empty picker", [])
      && opensOnCurrent("from wallpaper rows", wallpapers)
      && opensOnCurrent("from fewer theme rows", ImagePickerModel.loadRows(themeRows(4)))
    if (passed) console.log("THEME SELECTION PASS")
    Qt.callLater(function() { Qt.quit() })
  }
}
