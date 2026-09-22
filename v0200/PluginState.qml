import QtQuick
import Quickshell.Io
import "../omakit"

// One file the plugin keeps of its own, through omakit's Store block: the
// plugin's private 0700 directory under $XDG_STATE_HOME, reached by a
// descriptor walk with O_NOFOLLOW at every step, capped while reading and
// written through an exclusive staging file renamed into place.
//
// Store keeps a JSON value; the models here parse and serialise the text
// form, so this file bridges the two with the same round trip the models'
// own cloneState already makes. No schema is passed: Store then checks only
// that the file is JSON, which is what FileView + the model's parse did
// before, and the models keep doing the normalising and the bounds.
QtObject {
  id: state

  property string pluginId: ""
  property string name: ""
  // Where 0.8.x kept this file. Read once, when Store reports the private
  // copy missing, and written straight back through Store. The original is
  // left exactly where it is: a downgrade to 0.8.x keeps working, and
  // nothing is destroyed if the migration turns out to be wrong.
  property string legacyPath: ""

  readonly property bool loaded: _loaded
  readonly property string storePath: _storePath

  // The file's text, ready for the model that parses it. `unreadable` is
  // true only when the file is not JSON at all, which is the one case where
  // Store cannot hand back what it found.
  signal textReady(string text, bool unreadable)
  // A write that never reached the disk; the caller decides what to say.
  signal saveFailed(string reason)

  property bool _loaded: false
  property bool _migrated: false
  property string _storePath: ""

  function load() {
    if (!pluginId || !name) {
      _loaded = true
      textReady("", false)
      return
    }
    _store.read()
  }

  function save(text) {
    const value = _value(text)
    if (value === null) {
      saveFailed("the value is not JSON")
      return
    }
    _store.write(value)
  }

  function _text(value) {
    try {
      const text = JSON.stringify(value)
      return typeof text === "string" ? text : ""
    } catch (error) {
      return ""
    }
  }

  function _value(text) {
    try {
      const value = JSON.parse(String(text || ""))
      return value === undefined ? null : value
    } catch (error) {
      return null
    }
  }

  function _settle(text, unreadable) {
    _loaded = true
    textReady(text, unreadable === true)
  }

  function _onRead(result) {
    if (result.path) _storePath = String(result.path)
    if (result.state === "ok") {
      _settle(_text(result.value), false)
      return
    }
    // Nothing of ours there yet: this is where 0.8.x's file is adopted, once.
    if (result.state === "missing" && legacyPath && !_migrated) {
      _migrated = true
      _legacy.path = legacyPath
      _legacy.reload()
      // blockLoading blocks on access, not on reload(), so the read is taken
      // here rather than waited for: text() is "" when the 0.8.x file is not
      // there or cannot be read, which settles as the empty state.
      _adopt(_legacy.text())
      return
    }
    // missing with nothing to adopt is the empty state; so is a file Store
    // refused, which the caller reports rather than silently replacing.
    _settle("", result.state === "invalid")
  }

  // The 0.8.x file, read once and never written: the copy under the private
  // root is written through Store, like every other write.
  function _adopt(text) {
    const value = _value(text)
    if (value === null) {
      _settle("", false)
      return
    }
    _store.write(value)
    _settle(String(text || ""), false)
  }

  property Store _store: Store {
    pluginId: state.pluginId
    name: state.name
    kind: "state"
    onFinished: function(result) {
      if (result.op === "read") {
        state._onRead(result)
        return
      }
      if (result.op === "write" && result.state !== "ok")
        state.saveFailed(String(result.reason || result.state))
    }
  }

  // Read synchronously, once, and never written. An async FileView nested in
  // a QtObject never delivers onLoaded at all -- proved against a real
  // quickshell -- and blocking is what this read wants anyway: the migration
  // settles before anything else looks at the state, and the file is one
  // small JSON document read once per plugin start.
  property FileView _legacy: FileView {
    blockLoading: true
    preload: false
    printErrors: false
  }
}
