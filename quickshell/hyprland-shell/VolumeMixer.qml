import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// =====================================================================
// Per-app volume mixer popup for Hyprland.
// Ported from eww.yuck's (defwidget volume-mixer) / (defwindow
// volume-mixer) + scripts/mixer.sh.
//
// eww's mixer.sh polled `pactl list sink-inputs` / `pactl subscribe`
// to build {"master":..,"apps":[..]} JSON by hand. None of that is
// needed here -- Pipewire.nodes gives live PwNode objects directly, so
// master and per-app volume/mute are just property bindings that
// update themselves. PwObjectTracker replaces mixer.sh's `pactl
// subscribe` loop: any node passed to it gets kept up to date.
//
// Filtering: mixer.sh's per-app list came from `pactl list
// sink-inputs`, i.e. application *playback* streams only (not the
// sink itself, not recording streams). The equivalent here is
// `isStream && audio && !isSink` -- isSink is true for the hardware
// sink/source nodes AND for recording streams (they consume audio),
// false for nodes that push audio out (the sink itself's own
// isStream is false, so this leaves exactly the playback streams).
//
// NOTE: inline `component` declarations must live inside the file's
// root item (QML doesn't allow them as top-level siblings of it), so
// MixerSlider/MixerMuteButton are declared right inside the root
// PanelWindow below, ahead of everything that uses them.
// =====================================================================

PanelWindow {
    id: root

    component MixerSlider: Slider {
        id: slider

        // external source of truth in 0-100, set by the caller. Mirrors
        // eww's (scale :value volume ...) being driven by a poll/listen var.
        property real pct: 0
        property color highlightColor: Theme.blue
        // fired once the user releases the handle -- was eww's :onchange
        signal committed(real pct)

        orientation: Qt.Horizontal
        implicitHeight: 14
        from: 0
        to: 100
        value: pct

        // keep following external changes except while being dragged,
        // same trick Bar.qml's vertical volume slider uses
        Binding on value {
            value: slider.pct
            when: !slider.pressed
        }

        onMoved: slider.committed(slider.value)

        background: Rectangle {
            y: (slider.height - height) / 2
            width: slider.width
            height: 4
            radius: 2
            color: Theme.bg1

            Rectangle {
                width: parent.width * slider.visualPosition
                height: parent.height
                radius: 2
                color: slider.highlightColor
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: (slider.height - height) / 2
            implicitWidth: 12
            implicitHeight: 12
            radius: 6
            color: Theme.fg
        }
    }

    component MixerMuteButton: Item {
        id: btn

        property bool muted: false
        signal clicked()

        implicitWidth: 20
        implicitHeight: 20
        scale: muteArea.pressed ? 0.90 : (muteArea.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: muteArea.containsMouse ? Theme.bg1 : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }

        Text {
            anchors.centerIn: parent
            text: btn.muted ? "󰝟" : "󰕾" // same glyphs as eww.yuck's mixer-mute-btn
            color: btn.muted ? Theme.pink : (muteArea.containsMouse ? Theme.fg : Theme.fgDim)
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        MouseArea {
            id: muteArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }

    // shell.qml toggles this (was: `eww open --toggle volume-mixer`)
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

    screen: Quickshell.screens[0]
    color: "transparent"
    WlrLayershell.namespace: "quickshell:volume-mixer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // eww: :focusable false
    exclusionMode: ExclusionMode.Ignore

    anchors {
        bottom: true
        right: true
    }
    // eww: (defwindow volume-mixer :geometry (geometry :x "-70px"
    //       :y "-110px" :anchor "bottom right")) -- offsets the popup
    // up and clear of the 60px-wide bar, with a small gap.
    margins {
        right: 70
        bottom: 110
    }

    implicitWidth: 220
    implicitHeight: content.implicitHeight + 24

    // ---------- pipewire ----------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: !!(sink && sink.ready && sink.audio)
    readonly property int masterPct: sinkReady ? Math.round(sink.audio.volume * 100) : 0

    // Track every node up front. isStream/isSink/audio can report
    // missing or incorrect data on a node that isn't bound yet (see
    // PwNode.ready's docs), so filtering *before* tracking is a
    // chicken-and-egg problem -- track everything, then filter what's
    // actually wanted for the mixer UI.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // was: mixer.sh's `pactl list sink-inputs` loop. PwNodeType.AudioOutStream
    // maps 1:1 to pipewire's media.class == "Stream/Output/Audio", which is
    // exactly what `sink-inputs` lists (app playback streams, not the sink
    // itself and not recording/input streams).
    readonly property var appStreams: Pipewire.nodes.values.filter(n =>
        n.type === PwNodeType.AudioOutStream)


    Rectangle {
        anchors.fill: parent
        radius: 12
        opacity: root.reveal
        scale: 0.965 + 0.035 * root.reveal
        transform: Translate {
            x: 10 * (1.0 - root.reveal)
            y: 10 * (1.0 - root.reveal)
        }
        color: Theme.bg0
        border.color: Theme.bg1
        border.width: 1

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ================= master =================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "Master"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MixerMuteButton {
                        muted: root.sinkReady && root.sink.audio.muted
                        // was: scripts/mixer.sh master-mute
                        onClicked: if (root.sinkReady) root.sink.audio.muted = !root.sink.audio.muted
                    }
                }

                MixerSlider {
                    Layout.fillWidth: true
                    pct: root.masterPct
                    highlightColor: Theme.purple
                    // was: scripts/volume.sh set {}
                    onCommitted: (p) => { if (root.sinkReady) root.sink.audio.volume = p / 100 }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.bg1
            }

            // ================= per-app =================
            Text {
                visible: root.appStreams.length === 0
                text: "No apps playing audio"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: root.appStreams.length > 0

                Repeater {
                    model: root.appStreams

                    ColumnLayout {
                        id: appItem
                        opacity: 0.0
                        NumberAnimation on opacity {
                            from: 0.0; to: 1.0
                            duration: Theme.animNormal
                            easing.type: Easing.OutCubic
                        }
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                // was: application.name from pactl's sink-input properties
                                text: appItem.modelData.properties["application.name"]
                                      || appItem.modelData.description
                                      || appItem.modelData.name
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            MixerMuteButton {
                                muted: appItem.modelData.audio.muted
                                // was: scripts/mixer.sh app-mute <index>
                                onClicked: appItem.modelData.audio.muted = !appItem.modelData.audio.muted
                            }
                        }

                        MixerSlider {
                            Layout.fillWidth: true
                            pct: Math.round(appItem.modelData.audio.volume * 100)
                            highlightColor: Theme.blue
                            // was: scripts/mixer.sh app-set <index> {}
                            onCommitted: (p) => { appItem.modelData.audio.volume = p / 100 }
                        }
                    }
                }
            }
        }
    }
}
