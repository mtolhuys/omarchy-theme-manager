import QtQuick
import QtTest
import "runtime/ImagePickerModel.js" as ImagePickerModel

TestCase {
  id: suite
  name: "SignalCompatibility"
  property var received: null
  property bool sourceWasArray: false
  property list<var> typedRows: [{ name: "Example", apps: ["terminal"] }]
  signal delivered(var rows)
  signal listingDelivered(var listing)
  onDelivered: rows => {
    sourceWasArray = Array.isArray(rows)
    received = ImagePickerModel.signalRows(rows)
  }
  onListingDelivered: listing => { received = ImagePickerModel.signalRows(listing.rows) }

  function verifyRows(rows) {
    verify(Array.isArray(rows))
    compare(rows.length, 1)
    compare(rows[0].name, "Example")
    verify(Array.isArray(rows[0].apps))
    compare(rows[0].apps[0], "terminal")
  }

  function test_plainJavaScriptArray() {
    const rows = [{ name: "Example", apps: ["terminal"] }]
    verify(ImagePickerModel.signalRows(rows) === rows)
    verifyRows(ImagePickerModel.signalRows(rows))
  }

  function test_varSignal() {
    delivered([{ name: "Example", apps: ["terminal"] }])
    console.warn("SIGNAL_SOURCE_ARRAY=" + sourceWasArray)
    verifyRows(received)
  }

  function test_typedSequence() { verifyRows(ImagePickerModel.signalRows(typedRows)) }

  function test_listInsideMapSignal() {
    listingDelivered({ rows: [{ name: "Example", apps: ["terminal"] }] })
    verifyRows(received)
  }
}
