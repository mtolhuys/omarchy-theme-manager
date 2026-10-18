# Upstream boundary

`v0200/ImagePicker.qml` and `v0200/ImagePickerModel.js` are derived from
Omarchy's `omarchy.image-picker` at commit
`83881e979b35468c3e7d60b171e319ede61a88fd`.

At that revision, the upstream file hashes were:

- `ImagePicker.qml`:
  `0d882dcb6fc593d35fdfa6a9c4a87f04f5876dc2d221aac3eebf854f96dccedf`
- `ImagePickerModel.js`:
  `2eecf32b70811d0a39981e351ebe9843384aaf97b43dad1216651d2535a9a5da`

The theme and wallpaper models/controllers, filter UI, catalog and inventory
helpers, and tests are project-owned. `list.sh` remains equivalent to the
native image-picker helper.

The complete executable QML/JavaScript graph lives in one versioned runtime
directory so Qt cannot mix cached files from different plugin builds.

Before updating the derived files, compare them with
`$OMARCHY_PATH/shell/plugins/image-picker`, preserve both context-gated
integration paths, then run `npm run quality` and the disposable VM scenario
documented in the README.

The modern JavaScript syntax is intentional. Compatibility is protected by
tests and by running `qmllint` over both QML and imported JavaScript files.

## Qt 6.11 / 6.12 compatibility evidence

The local package log records the 2026-10-18 update at 15:19 Europe/Amsterdam:
Qt base/declarative 6.11.2 to 6.12.0, Quickshell 0.3.1 to 0.3.2, and Omarchy
4.0.4 to 4.0.5. Later that afternoon the system switched to the Omarchy dev
package. Timing alone cannot identify which component changed behavior.

An isolated Qt-only comparison does: the same QML `signal delivered(var rows)`
receives an ordinary JavaScript array on Qt 6.11.2 (`Array.isArray=true`) and a
sequence on Qt 6.12.0 (`Array.isArray=false`). Both preserve the list contents.
The old Qt libraries and runner were extracted from cached packages into a
temporary directory; no installed library was downgraded, no Quickshell process
was involved, and no desktop window was opened. Qt's documentation explicitly
allows [array-like values from Qt list conversion](https://doc.qt.io/qt-6/qtqml-cppintegration-data.html#qvariantlist-and-qvariantmap-to-javascript-array-like-and-object).
The plugin's assumption that every delivered list was a native array caused
the silent discard. Normalize at the boundary rather than branching on version.

`tests/qt_compatibility_test.py` runs the real Qt test runner against
`tests/qml/tst_signal-compatibility.qml`. Its checks cover JavaScript arrays,
var signals, typed sequences, lists inside maps, and nested lists. This test
runs in `npm run quality` on the installed Qt version. To test a separately
extracted trusted Qt package prefix without changing the installed runtime:

```bash
OMARCHY_QT_COMPAT_ROOT=/path/to/extracted/prefix \
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p qt_compatibility_test.py
```

The suite passed on both Qt 6.11.2 and 6.12.0 on 2026-10-18. The additional
windowless controller test covers the actual Quickshell/Run/signal path.

## Wallpaper selection and application are separate contracts

The current host's `bin/omarchy-theme-bg-switcher` returns a selected filename.
Its normal callers (`default/omarchy/omarchy-menu.jsonc`, `style.background`, and
`shell/plugins/background/Background.qml`) then invoke `omarchy-theme-bg-set`.
Theme Manager's cross-navigation starts the switcher itself, so it cannot
assume that a caller will apply its output.

Wallpaper selections now invoke the absolute `omarchy-theme-bg-set` command
through `WallpaperApplyController` and Run (15-second deadline, 64 KiB output
cap). Only a successful command completes the waiting selector and remembers
the choice. Failure keeps the picker open with its selection files intact for
retry. Cancelled or replaced requests cannot complete a newer picker. Generic
image selection retains the filename-only contract. Downloaded/folder images
first pass through the existing descriptor-bound publication helper, then the
same apply path as local images.

After a host update, run `npm run quality`, then verify the live picker using
real input: catalog browsing/search, opening and cancelling install confirmation,
wallpaper pagination, and selecting a different wallpaper. Confirm both the
current-background link and the shell's live background, then restore the original.
A filename returned to a caller or a successful thumbnail preview is not proof
that a wallpaper was applied.

After a plugin update, check `runtimeIdentity` as well as the installed commit.
This host retained an old QML component after a same-path rescan; one shell
restart loaded the updated identity. Never report the installed version as the
running version without that check.
