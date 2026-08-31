import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// =====================================================================
// Wallpaper picker popup for Hyprland.
// Ported from eww.yuck's (defwidget wallpaper-popup) / (defwindow
// wallpaper-popup) + scripts/wallpaper.sh.
//
// What changed vs. the eww/X11 version:
//
// - Listing wallpapers: wallpaper.sh's `list` action globbed WALL_DIR
//   by hand and pre-chunked the results into rows of $COLS=3 (again,
//   because eww's `for` can't wrap a flat list into a grid), refreshed
//   by a slow 300s poll. FolderListModel (a real Qt type, not a
//   script) replaces all of that: `wallpapers` below is a flat,
//   automatically-3-wide-wrapped GridView model that updates itself
//   the instant a file is added to/removed from the folder, via
//   QFileSystemWatcher under the hood -- no poll interval to tune.
//
// - Setting the wallpaper: X11 has one universal way to paint the
//   desktop background (the root window), which is all `xwallpaper
//   --zoom` did. Wayland has no equivalent -- painting the background
//   is just an ordinary layer-shell client, so *some* wallpaper daemon
//   has to already be running for anything to set. This picker targets
//   `swww` (the most common choice in the Hyprland community: supports
//   live switching + transitions via a simple CLI, unlike `swaybg`
//   which has to be restarted per image). Add to hyprland.conf:
//     exec-once = swww-daemon
//   `hyprpaper` is a reasonable alternative if you'd rather stay
//   entirely within Hyprland's own tooling; swapping it in just means
//   changing the one `Quickshell.execDetached([...])` call in
//   `setWallpaper()` below to hyprpaper's `hyprctl hyprpaper wallpaper`
//   IPC call instead.
//
// - Restoring on login: wallpaper.sh cached the last-picked file into
//   WALL_DIR/Cache so a separate `wallpaper_apply_cache.sh` (referenced
//   in that script's header, wired into ~/.xinitrc) could re-apply it
//   next login. That script wasn't part of what got ported here, so
//   the Cache-dir bookkeeping is kept (see `cacheWallpaper()` below)
//   but nothing reads it back yet -- add something like this to
//   hyprland.conf to actually restore on login, mirroring what
//   wallpaper_apply_cache.sh presumably did:
//     exec-once = sh -c 'f="$HOME/Pictures/Wallpapers/Cache"/*; swww img "$f"'
//   (after `exec-once = swww-daemon`, and once swww-daemon has had a
//   moment to start -- swww's own docs cover sequencing this reliably).
//
// - Opening the popup: wallpaper.sh's `list`/`set` actions were driven
//   by a `super+w` sxhkd bind and yuck's own :onclick, both calling
//   straight into the eww/bspwm world. Hyprland binds can't call a
//   QML function directly, so this exposes the same toggle over
//   Quickshell's IPC instead -- add to hyprland.conf:
//     bind = SUPER, W, exec, qs ipc call wallpaper toggle
//   (adjust `qs ipc call wallpaper toggle` to `qs -c <config-name> ipc
//   call wallpaper toggle` if quickshell isn't running as the default
//   config).
//
// Like the original (:focusable false), this popup never grabs
// keyboard focus -- it's click-only, same as PowerMenu.qml.
// =====================================================================

PanelWindow {
    id: root

    // was: WALL_DIR in scripts/wallpaper.sh
    readonly property string wallpaperDir: "/home/snow/Pictures/Wallpapers"
    // was: CACHE_DIR in scripts/wallpaper.sh
    readonly property string cacheDir: root.wallpaperDir + "/Cache"

    // was: `(defpoll wallpapers :interval "300s" "scripts/wallpaper.sh list")`
    // -- live-updating instead of polled, see header comment above.
    FolderListModel {
        id: wallpapers
        folder: "file://" + root.wallpaperDir
        showDirs: false               // excludes Cache/ automatically
        showDotAndDotDot: false
        caseSensitive: false          // was: `shopt -s nocaseglob` in wallpaper.sh
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.webp"]
        sortField: FolderListModel.Name
    }

    property bool open: false
    function toggle() { root.open = !root.open }
    // Animate the surface itself instead of instantly destroying it on close.
    property real reveal: root.open ? 1.0 : 0.0
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.animNormal : Theme.animFast
            easing.type: root.open ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: root.open || root.reveal > 0.001

    // Close this popup when the user clicks anywhere outside it.
    HyprlandFocusGrab {
        id: outsideClickGrab
        windows: [root]
        active: root.open
        onCleared: {
            if (root.open)
                root.open = false
        }
    }

    // was: `xwallpaper --zoom "$path"` + wallpaper.sh's Cache-dir
    // bookkeeping for wallpaper_apply_cache.sh (see header comment above)
    function setWallpaper(path) {
        root.open = false; // was: "; eww close wallpaper-popup" on the :onclick
        Quickshell.execDetached(["awww", "img", path])
        root.cacheWallpaper(path)
    }

    // was: `mkdir -p "$CACHE_DIR"; rm -f "$CACHE_DIR"/*; cp -f "$path" "$CACHE_DIR/"`
    // Split into argv-only Process calls (no `bash -c` string built from
    // `path`) so a wallpaper filename can never be interpreted as shell
    // syntax -- `find -delete` replaces the `rm -f dir/*` glob, since a
    // literal argv has no globbing to do it for us.
    function cacheWallpaper(path) {
        Quickshell.execDetached(["mkdir", "-p", root.cacheDir])
        Quickshell.execDetached(["find", root.cacheDir, "-maxdepth", "1", "-type", "f", "-delete"])
        Quickshell.execDetached(["cp", "-f", path, root.cacheDir + "/"])
    }

    // was: wallpaper.sh's `open`-equivalent trigger, bound to `super+w`
    // in sxhkdrc. See the header comment above for the matching
    // hyprland.conf line.
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle() }
        function open(): void { if (!root.open) root.toggle() }
        function close(): void { if (root.open) root.open = false }
    }

    // eww: (defwindow wallpaper-popup :monitor 0 :geometry (geometry
    //       :x "0px" :y "0px" :width "1200px" :height "820px"
    //       :anchor "center") :stacking "overlay" :focusable false)
    // Same whole-screen-cover-then-center-a-card trick as EmojiPicker.qml
    // (PanelWindow has no direct "anchor: center") -- see that file's
    // header for why.
    screen: Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wallpaper-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // eww: :focusable false
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.centerIn: parent
        implicitWidth: 1200
        opacity: root.reveal
        scale: 0.965 + 0.035 * root.reveal
        transform: Translate {
            x: 0 * (1.0 - root.reveal)
            y: 14 * (1.0 - root.reveal)
        }
        implicitHeight: 820
        radius: 16
        color: Theme.bg0
        border.color: Theme.bg1
        border.width: 1

        // eww: (label :class "wallpaper-title" ...) / (box :class
        // "wallpaper-divider") / (scroll ... (wallpaper-grid))
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            Text {
                text: "Wallpaper"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.bg1
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: width / 3    // was: COLS=3 in wallpaper.sh
                cellHeight: 226
                model: wallpapers

                populate: Transition {
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animSlow }
                    NumberAnimation { property: "scale"; from: 0.97; to: 1.0; duration: Theme.animSlow; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: cell
                    required property string filePath
                    required property url fileUrl
                    required property string fileBaseName
                    width: grid.cellWidth
                    height: grid.cellHeight

                    // eww: (button :class "wallpaper-item" :onclick
                    // "scripts/wallpaper.sh set '${path}'; eww close
                    // wallpaper-popup" (box (image ...) (label ...)))
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 7   // was: :spacing 14 between rows/cols
                        radius: 10
                        scale: cellArea.pressed ? 0.975 : (cellArea.containsMouse ? 1.018 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: cellArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Image {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 190
                                source: cell.fileUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // downsamples on load instead of decoding
                                // full-res -- wallpaper.sh had no thumbnail
                                // cache either, it just let GTK scale the
                                // full image; this is the QML equivalent
                                sourceSize.width: 340
                                sourceSize.height: 190
                                // eww's `.wallpaper-thumb { border-radius:
                                // 8px }` isn't replicated -- rounding an
                                // Image's corners needs an extra masking
                                // step (Qt5Compat.GraphicalEffects'
                                // OpacityMask, or a shader) that felt like
                                // more machinery than a cosmetic corner
                                // radius is worth here. Square thumbnails.
                            }

                            Text {
                                Layout.fillWidth: true
                                text: cell.fileBaseName
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                            }
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.setWallpaper(cell.filePath)
                        }
                    }
                }
            }
        }
    }
}
