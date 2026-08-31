import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    property bool open: false
    property int thumbnailGeneration: 0

    function toggle() {
        root.open = !root.open
        if (root.open)
            root.refresh()
    }

    function show() {
        root.open = true
        root.refresh()
    }

    function hide() {
        root.open = false
    }

    function refresh() {
        if (!listProcess.running)
            listProcess.exec(["cliphist", "list"])
    }

    function populateHistory(output) {
        clipboardModel.clear()

        const lines = output.split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (!line.length)
                continue

            const tab = line.indexOf("\t")
            if (tab < 0)
                continue

            const id = line.substring(0, tab)
            const preview = line.substring(tab + 1)
            const imageEntry = preview.indexOf("[[ binary data ") === 0

            clipboardModel.append({
                clipId: id,
                rawLine: line,
                previewText: imageEntry ? "Image" : preview,
                isImage: imageEntry,
                previewPath: imageEntry ? ("/tmp/quickshell-cliphist-" + id) : ""
            })
        }

        // Decode image entries to temporary files after the model exists.
        thumbnailGeneration = 0
        if (!thumbnailProcess.running)
            thumbnailProcess.exec(["bash", "-lc",
                "while IFS= read -r line; do " +
                "id=\"${line%%$'\\t'*}\"; preview=\"${line#*$'\\t'}\"; " +
                "if [[ \"$preview\" == '[[ binary data '* ]]; then " +
                "printf '%s\\n' \"$line\" | cliphist decode > \"/tmp/quickshell-cliphist-$id\"; " +
                "fi; done < <(cliphist list)"
            ])
    }

    function copyEntry(rawLine) {
        copyProcess.exec(["bash", "-lc",
            "printf '%s\\n' \"$1\" | cliphist decode | wl-copy",
            "quickshell-clipboard", rawLine
        ])
        root.open = false
    }

    function deleteEntry(rawLine) {
        deleteProcess.exec(["bash", "-lc",
            "printf '%s\\n' \"$1\" | cliphist delete",
            "quickshell-clipboard", rawLine
        ])
    }

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
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:clipboard-history"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        bottom: true
    }

    margins {
        bottom: 18
    }

    implicitWidth: 560
    implicitHeight: 360

    IpcHandler {
        target: "clipboard"

        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function refresh(): void { root.refresh() }
    }

    ListModel {
        id: clipboardModel
    }

    // These watchers make the component self-contained: text and image
    // clipboard changes are stored by cliphist for this session.
    Process {
        id: textWatcher
        running: true
        command: ["bash", "-lc", "command -v cliphist >/dev/null && command -v wl-paste >/dev/null && exec wl-paste --type text --watch cliphist store"]
    }

    Process {
        id: imageWatcher
        running: true
        command: ["bash", "-lc", "command -v cliphist >/dev/null && command -v wl-paste >/dev/null && exec wl-paste --type image --watch cliphist store"]
    }

    Process {
        id: listProcess
        stdout: StdioCollector {
            onStreamFinished: root.populateHistory(this.text)
        }
    }

    Process {
        id: thumbnailProcess
        onRunningChanged: {
            if (!running)
                root.thumbnailGeneration = Date.now()
        }
    }

    Process {
        id: copyProcess
    }

    Process {
        id: deleteProcess
        onRunningChanged: {
            if (!running && root.open)
                root.refresh()
        }
    }

    Process {
        id: wipeProcess
        onRunningChanged: {
            if (!running) {
                clipboardModel.clear()
                root.thumbnailGeneration = 0
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        opacity: root.reveal
        scale: 0.965 + 0.035 * root.reveal
        transform: Translate {
            x: 0 * (1.0 - root.reveal)
            y: 14 * (1.0 - root.reveal)
        }
        color: Theme.bg0
        border.width: 1
        border.color: Theme.bg1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Clipboard"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    text: clipboardModel.count + (clipboardModel.count === 1 ? " item" : " items")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 8
                    scale: refreshArea.pressed ? 0.92 : (refreshArea.containsMouse ? 1.06 : 1.0)
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    color: refreshArea.containsMouse ? Theme.bg1 : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.refresh()
                    }
                }

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 8
                    scale: clearArea.pressed ? 0.92 : (clearArea.containsMouse ? 1.06 : 1.0)
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    color: clearArea.containsMouse ? Theme.bg1 : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰆴"
                        color: Theme.pink
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: wipeProcess.exec(["cliphist", "wipe"])
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.bg1
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: clipboardList
                    anchors.fill: parent
                    clip: true
                    spacing: 7
                    model: clipboardModel
                    boundsBehavior: Flickable.StopAtBounds

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animNormal }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0.0; duration: Theme.animFast }
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: entry
                        required property string clipId
                        required property string rawLine
                        required property string previewText
                        required property bool isImage
                        required property string previewPath

                        width: clipboardList.width - (clipboardList.ScrollBar.vertical.visible ? 10 : 0)
                        height: isImage ? 96 : 62
                        radius: 10
                        scale: entryArea.pressed ? 0.985 : (entryArea.containsMouse ? 1.012 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: entryArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        border.width: 1
                        border.color: entryArea.containsMouse ? Theme.bg2 : Theme.bg1

                        RowLayout {
                            z: 2
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Rectangle {
                                visible: entry.isImage
                                Layout.preferredWidth: 86
                                Layout.fillHeight: true
                                radius: 7
                                color: Theme.bg1
                                clip: true

                                Image {
                                    id: thumbImage
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    // Only assign a URL once this row has a real thumbnail path.
                                    // Without this guard an empty previewPath becomes file:///,
                                    // which makes QQuickImage try to open the filesystem root.
                                    source: entry.isImage
                                            && entry.previewPath.length > 1
                                            && entry.previewPath !== "/"
                                            && root.thumbnailGeneration > 0
                                            ? ("file://" + entry.previewPath + "?v=" + root.thumbnailGeneration)
                                            : ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: thumbImage.status !== Image.Ready
                                    text: "󰋩"
                                    color: Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 22
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 3

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.isImage ? "Image" : entry.previewText
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: entry.isImage
                                    maximumLineCount: entry.isImage ? 1 : 2
                                    elide: Text.ElideRight
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: entry.isImage
                                    text: "Click to copy image"
                                    color: Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 7
                                scale: deleteArea.pressed ? 0.92 : (deleteArea.containsMouse ? 1.08 : 1.0)
                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                                color: deleteArea.containsMouse ? Theme.bg2 : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                z: 3

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: deleteArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: mouse => {
                                        mouse.accepted = true
                                        root.deleteEntry(entry.rawLine)
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: entryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            z: 1
                            onClicked: root.copyEntry(entry.rawLine)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: clipboardModel.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰅌"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Clipboard history is empty"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Click an entry to copy it • Esc closes"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
