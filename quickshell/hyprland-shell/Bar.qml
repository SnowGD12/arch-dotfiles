import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

// =====================================================================
// Vertical status bar (right edge) for Hyprland.
// Ported from eww.yuck's (defwindow bar). The volume-mixer and
// power-menu popups are wired up too, via VolumeMixer.qml/PowerMenu.qml
// + the toggle-request signals below -- see shell.qml for how they're
// connected.
// The emoji picker and wallpaper picker (eww: emoji-popup,
// wallpaper-popup) are also ported -- see EmojiPicker.qml /
// WallpaperPicker.qml, both instantiated in shell.qml. Neither has a
// bar button (same as the originals, which only ever opened via
// sxhkd binds -- super+e and super+w respectively); both are toggled
// over Quickshell IPC instead -- see each file's header for its
// hyprland.conf bind.
// The remaining popup eww.yuck used to open (calendar-popup) is NOT
// included. Its trigger button is kept but stubbed (see the remaining
// TODO comment below) -- see this project's README for what would be
// involved in porting it separately.
// =====================================================================

PanelWindow {
    id: root

    // was: `eww open --toggle volume-mixer`. shell.qml connects this to
    // the VolumeMixer popup's toggle() -- see that file's header.
    signal volumeMixerToggleRequested()

    // was: `eww open --toggle power-menu`. shell.qml connects this to
    // the PowerMenu popup's toggle() -- see that file's header.
    signal powerMenuToggleRequested()

    // Toggle the combined calendar / notification-history popup.
    signal calendarToggleRequested()

    // The original eww config only ever opened `:monitor 0`. To put a
    // bar on every monitor instead, delete this `screen:` line, move
    // this whole file's content into a component, and instantiate it
    // from shell.qml with:
    //   Variants { model: Quickshell.screens; delegate: Bar {} }
    screen: Quickshell.screens[0]

    anchors {
        top: true
        bottom: true
        right: true
    }

    implicitWidth: Theme.barWidth
    exclusiveZone: Theme.exclusiveZone
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"
    WlrLayershell.layer: WlrLayer.Top

    // ---------- pipewire (default sink) ----------
    // Replaces scripts/volume.sh's `pactl` polling with Quickshell's
    // native Pipewire binding.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: !!(sink && sink.ready && sink.audio)
    readonly property int volumePct: sinkReady ? Math.round(sink.audio.volume * 100) : 0

    // ---------- clock ----------
    // Replaces the two `(defpoll hh/mm ... "date ...")` pollers.
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // background + rounded corners (PanelWindow itself must stay
    // transparent for this to work -- see Quickshell's rounded-window FAQ)
    Rectangle {
        id: barSurface
        anchors.fill: parent
        opacity: 0.0
        NumberAnimation on opacity {
            from: 0.0; to: 1.0
            duration: Theme.animSlow
            easing.type: Easing.OutCubic
        }
        transform: Translate {
            x: Theme.barWidth
            NumberAnimation on x {
                from: Theme.barWidth; to: 0
                duration: Theme.animSlow
                easing.type: Easing.OutCubic
            }
        }
        // Only round the corners facing away from the screen edge (left) --
        // the right corners sit flush against the screen edge anyway, so
        // rounding them would just be invisible/wasted.
        topLeftRadius: 12
        bottomLeftRadius: 12
        topRightRadius: 0
        bottomRightRadius: 0
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 0

            // ================= logo =================
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10
                implicitWidth: 32
                implicitHeight: 32
                scale: logoArea.pressed ? 0.94 : (logoArea.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: logoArea.containsMouse ? Theme.bg1 : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                Text {
                    anchors.centerIn: parent
                    text: "󰣇" // same Arch Linux glyph as the original eww bar
                    color: Theme.purple
                    font.family: Theme.fontFamily
                    font.pixelSize: 25
                }
                MouseArea {
                    id: logoArea
                    anchors.fill: parent
                    hoverEnabled: true
                    // was: `eww open --toggle power-menu`
                    onClicked: root.powerMenuToggleRequested()
                }
            }

            // ================= workspaces =================
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Repeater {
                    // Hyprland.workspaces is already sorted by id, just
                    // like eww's workspaces.sh emitted them in bspwm-id order.
                    model: Hyprland.workspaces

                    Rectangle {
                        id: wsItem
                        required property var modelData
                        readonly property bool isFocused: modelData.focused
                        readonly property bool isUrgent: modelData.urgent
                        readonly property bool isOccupied: modelData.toplevels.count > 0

                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 6
                        scale: isFocused ? 1.08 : (wsArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: isFocused ? Theme.blue : isUrgent ? Theme.pink
                             : wsArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: wsItem.modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: wsItem.isFocused
                            color: (wsItem.isFocused || wsItem.isUrgent) ? Theme.bg0
                                 : wsItem.isOccupied ? Theme.fg
                                 : Theme.bg2
                        }

                        MouseArea {
                            id: wsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            // was: bspc desktop -f ${id}
                            onClicked: wsItem.modelData.activate()
                        }
                    }
                }
            }

            // empty, expanding middle -- pushes tray/volume/clock to the bottom
            Item { Layout.fillHeight: true }

            // ================= systray =================
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10
                spacing: 6

                Repeater {
                    model: SystemTray.items

                    Item {
                        id: trayItem
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 18
                        implicitHeight: 18
                        scale: trayArea.pressed ? 0.92 : (trayArea.containsMouse ? 1.12 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                        Image {
                            anchors.fill: parent
                            visible: trayItem.modelData.icon !== ""
                            source: trayItem.modelData.icon
                            sourceSize: Qt.size(18, 18)
                        }

                        // Read the tray item's DBus menu ourselves instead of using
                        // SystemTrayItem.display(). display() creates a native Qt menu,
                        // which is why it ignored the shell theme and could be positioned
                        // at the compositor's top-right corner.
                        QsMenuOpener {
                            id: trayMenuOpener
                            menu: trayItem.modelData.menu
                        }

                        PopupWindow {
                            id: trayMenuPopup
                            visible: false
                            color: "transparent"
                            implicitWidth: 240
                            implicitHeight: Math.max(42, trayMenuColumn.implicitHeight + 16)
                            width: implicitWidth
                            height: implicitHeight
                            grabFocus: true

                            // The bar lives on the right edge, so grow the menu to the
                            // LEFT of the exact icon that was clicked. Quickshell will
                            // flip/slide it if the icon is too close to a screen edge.
                            anchor.item: trayItem
                            anchor.edges: Edges.Left | Edges.Top
                            anchor.gravity: Edges.Left | Edges.Bottom
                            anchor.margins.left: 10
                            anchor.adjustment: PopupAdjustment.All

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: Theme.bg0
                                border.width: 1
                                border.color: Theme.bg2

                                Column {
                                    id: trayMenuColumn
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 2

                                    Repeater {
                                        model: trayMenuOpener.children

                                        delegate: Item {
                                            id: menuEntry
                                            required property var modelData
                                            width: trayMenuColumn.width
                                            height: modelData.isSeparator ? 9 : 34

                                            Rectangle {
                                                visible: menuEntry.modelData.isSeparator
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 12
                                                height: 1
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                color: Theme.bg2
                                            }

                                            Rectangle {
                                                visible: !menuEntry.modelData.isSeparator
                                                anchors.fill: parent
                                                radius: 8
                                                color: menuEntryArea.containsMouse
                                                       ? Theme.bg1 : "transparent"
                                                opacity: menuEntry.modelData.enabled ? 1.0 : 0.42

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 9
                                                    anchors.rightMargin: 9
                                                    spacing: 8

                                                    Item {
                                                        Layout.preferredWidth: 18
                                                        Layout.preferredHeight: 18

                                                        Image {
                                                            anchors.fill: parent
                                                            source: menuEntry.modelData.icon
                                                            sourceSize: Qt.size(18, 18)
                                                            fillMode: Image.PreserveAspectFit
                                                            visible: source.toString() !== ""
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            visible: menuEntry.modelData.icon === ""
                                                                     && menuEntry.modelData.checkState === Qt.Checked
                                                            text: "󰄬"
                                                            color: Theme.blue
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 13
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: menuEntry.modelData.text
                                                        color: menuEntryArea.containsMouse
                                                               ? Theme.fg : Theme.fg
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    Text {
                                                        visible: menuEntry.modelData.hasChildren
                                                        text: "󰅂"
                                                        color: Theme.fgDim
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                    }
                                                }

                                                MouseArea {
                                                    id: menuEntryArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: menuEntry.modelData.enabled
                                                    onClicked: {
                                                        if (menuEntry.modelData.hasChildren) {
                                                            // Keep application-provided submenus functional.
                                                            // The main tray menu remains custom/styled.
                                                            const p = root.mapFromItem(menuEntry, 0, 0)
                                                            menuEntry.modelData.display(root, p.x - 240, p.y)
                                                        } else {
                                                            menuEntry.modelData.triggered()
                                                        }
                                                        trayMenuPopup.visible = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: trayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    if (trayItem.modelData.hasMenu) {
                                        trayMenuPopup.anchor.updateAnchor()
                                        trayMenuPopup.visible = !trayMenuPopup.visible
                                    }
                                } else {
                                    trayMenuPopup.visible = false
                                    if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu) {
                                        trayMenuPopup.anchor.updateAnchor()
                                        trayMenuPopup.visible = true
                                    } else {
                                        trayItem.modelData.activate()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ================= volume =================
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.volumePct + "%"
                    color: volPctArea.containsMouse ? Theme.blue : Theme.fgDim
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    font.family: Theme.fontFamily
                    font.pixelSize: 10

                    MouseArea {
                        id: volPctArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // was: `eww open --toggle volume-mixer`
                        onClicked: root.volumeMixerToggleRequested()
                    }
                }

                Slider {
                    id: volSlider
                    Layout.alignment: Qt.AlignHCenter
                    orientation: Qt.Vertical
                    implicitHeight: 80
                    implicitWidth: 16
                    from: 0
                    to: 100
                    value: root.volumePct

                    // keep the handle following external volume changes
                    // (e.g. the wheel handler below) except while being dragged
                    Binding on value {
                        value: root.volumePct
                        when: !volSlider.pressed
                    }

                    onMoved: {
                        if (root.sinkReady)
                            root.sink.audio.volume = value / 100
                    }

                    background: Rectangle {
                        x: (volSlider.width - width) / 2
                        width: 4
                        radius: 2
                        color: Theme.bg1
                        Rectangle {
                            width: parent.width
                            height: parent.height * (1 - volSlider.visualPosition)
                            anchors.bottom: parent.bottom
                            radius: 2
                            color: Theme.blue
                        }
                    }

                    handle: Rectangle {
                        x: (volSlider.width - width) / 2
                        y: volSlider.topPadding + volSlider.visualPosition
                           * (volSlider.availableHeight - height)
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: 6
                        color: Theme.fg
                    }

                    // scroll-wheel volume, mirrors eww's `(eventbox :onscroll ...)`
                    WheelHandler {
                        onWheel: (event) => {
                            if (!root.sinkReady) return
                            const step = 0.05
                            const delta = event.angleDelta.y > 0 ? step : -step
                            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + delta))
                        }
                    }
                }
            }

            // ================= clock =================
            Item {
                id: clockButton
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 52
                implicitHeight: clockColumn.implicitHeight + 6
                scale: clockArea.pressed ? 0.97 : (clockArea.containsMouse ? 1.03 : 1.0)
                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: clockArea.containsMouse ? Theme.bg1 : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                ColumnLayout {
                    id: clockColumn
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(root.now, "HH")
                        color: clockArea.containsMouse ? Theme.blue : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(root.now, "mm")
                        color: clockArea.containsMouse ? Theme.blue : Theme.fgDim
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                }

                MouseArea {
                    id: clockArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.calendarToggleRequested()
                }
            }
        }
    }
}
