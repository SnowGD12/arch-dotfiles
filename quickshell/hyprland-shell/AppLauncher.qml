import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    property bool open: false
    property real reveal: root.open ? 1.0 : 0.0
    property string query: searchField.text

    function toggle() {
        if (root.open)
            root.hide()
        else
            root.show()
    }

    function show() {
        root.open = true
        searchField.text = ""
        appList.currentIndex = filteredApps.values.length > 0 ? 0 : -1
        Qt.callLater(function() {
            searchField.forceActiveFocus()
        })
    }

    function hide() {
        root.open = false
    }

    function normalized(value) {
        return (value || "").toString().toLowerCase()
    }

    // Some .desktop files reference icon names that are not present in the
    // active icon theme. Sending those names to Quickshell.iconPath() makes
    // the icon provider print a warning on every launcher load.
    function missingThemeIcon(iconName) {
        return iconName === "input-keyboard"
            || iconName === "hwloc"
            || iconName === "network-wired"
            || iconName === "preferences-desktop-theme"
    }

    function fallbackIconGlyph(iconName) {
        switch (iconName) {
        case "input-keyboard":
            return "󰌌"
        case "hwloc":
            return "󰍛"
        case "network-wired":
            return "󰈀"
        case "preferences-desktop-theme":
            return "󰏘"
        default:
            return "󰘔"
        }
    }

    function score(entry, needle) {
        if (!needle.length)
            return 0

        const name = normalized(entry.name)
        const generic = normalized(entry.genericName)
        const id = normalized(entry.id)
        const keywords = entry.keywords ? normalized(entry.keywords.join(" ")) : ""
        const comment = normalized(entry.comment)

        if (name === needle)
            return 0
        if (name.indexOf(needle) === 0)
            return 1
        if (generic.indexOf(needle) === 0)
            return 2
        if (name.indexOf(needle) >= 0)
            return 3
        if (generic.indexOf(needle) >= 0)
            return 4
        if (keywords.indexOf(needle) >= 0)
            return 5
        if (id.indexOf(needle) >= 0)
            return 6
        if (comment.indexOf(needle) >= 0)
            return 7
        return 999
    }

    function buildFilteredApps() {
        const needle = normalized(root.query).trim()
        let apps = [...DesktopEntries.applications.values]

        if (needle.length) {
            apps = apps.filter(function(entry) {
                return root.score(entry, needle) < 999
            })
        }

        apps.sort(function(a, b) {
            if (needle.length) {
                const sa = root.score(a, needle)
                const sb = root.score(b, needle)
                if (sa !== sb)
                    return sa - sb
            }
            return normalized(a.name).localeCompare(normalized(b.name))
        })

        return apps
    }

    function launchIndex(index) {
        if (index < 0 || index >= filteredApps.values.length)
            return

        const entry = filteredApps.values[index]
        if (!entry)
            return

        root.hide()
        entry.execute()
    }

    function launchCurrent() {
        root.launchIndex(appList.currentIndex)
    }

    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.animNormal : Theme.animFast
            easing.type: root.open ? Easing.OutCubic : Easing.InCubic
        }
    }

    visible: root.open || root.reveal > 0.001
    screen: Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:app-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        left: true
    }

    margins {
        top: Math.max(10, Math.round((root.screen.height - root.implicitHeight) / 2))
        left: Math.max(10, Math.round((root.screen.width - root.implicitWidth) / 2))
    }

    implicitWidth: 540
    implicitHeight: 430

    HyprlandFocusGrab {
        id: outsideClickGrab
        windows: [root]
        active: root.open
        onCleared: {
            if (root.open)
                root.hide()
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
    }

    ScriptModel {
        id: filteredApps
        values: root.buildFilteredApps()
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 16
        color: Theme.bg0
        border.width: 1
        border.color: Theme.bg2
        opacity: root.reveal
        scale: 0.96 + (0.04 * root.reveal)

        transform: Translate {
            y: -12 * (1.0 - root.reveal)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 11
                color: Theme.bg1
                border.width: searchField.activeFocus ? 1 : 0
                border.color: Theme.blue

                Behavior on border.width {
                    NumberAnimation { duration: Theme.animFast }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: "󰍉"
                        color: searchField.activeFocus ? Theme.blue : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 19

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        focus: root.open
                        placeholderText: "Search applications..."
                        color: Theme.fg
                        placeholderTextColor: Theme.fgDim
                        selectionColor: Theme.blue
                        selectedTextColor: Theme.bg0
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        background: Item {}

                        onTextChanged: {
                            appList.currentIndex = filteredApps.values.length > 0 ? 0 : -1
                            appList.positionViewAtBeginning()
                        }

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) {
                                root.hide()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                if (filteredApps.values.length > 0) {
                                    appList.currentIndex = Math.min(appList.currentIndex + 1, filteredApps.values.length - 1)
                                    appList.positionViewAtIndex(appList.currentIndex, ListView.Contain)
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_Backtab)) {
                                if (filteredApps.values.length > 0) {
                                    appList.currentIndex = Math.max(appList.currentIndex - 1, 0)
                                    appList.positionViewAtIndex(appList.currentIndex, ListView.Contain)
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.launchCurrent()
                                event.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        visible: searchField.text.length > 0
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 7
                        color: clearArea.containsMouse ? Theme.bg2 : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3

                Text {
                    text: root.query.length ? "Applications" : "All applications"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: filteredApps.values.length + (filteredApps.values.length === 1 ? " result" : " results")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: appList
                    anchors.fill: parent
                    clip: true
                    spacing: 5
                    model: filteredApps
                    currentIndex: filteredApps.values.length > 0 ? 0 : -1
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: Theme.animFast
                    highlightResizeDuration: Theme.animFast

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: appDelegate
                        required property var modelData
                        required property int index

                        width: appList.width - 8
                        height: 58
                        radius: 10
                        color: appList.currentIndex === index
                               ? Theme.bg2
                               : (appArea.containsMouse ? Theme.bg1 : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 10
                            spacing: 11

                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: 9
                                color: Theme.bg1

                                Image {
                                    id: appIconImage
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    visible: !root.missingThemeIcon(appDelegate.modelData.icon || "")
                                    source: visible
                                            ? Quickshell.iconPath(appDelegate.modelData.icon || "application-x-executable", "application-x-executable")
                                            : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !appIconImage.visible
                                    text: root.fallbackIconGlyph(appDelegate.modelData.icon || "")
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 22
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: appDelegate.modelData.name || appDelegate.modelData.id
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: appDelegate.modelData.genericName || appDelegate.modelData.comment || ""
                                    color: Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                text: "󰌑"
                                color: appList.currentIndex === index ? Theme.blue : Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                opacity: appList.currentIndex === index || appArea.containsMouse ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.animFast }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: Theme.animFast }
                                }
                            }
                        }

                        MouseArea {
                            id: appArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: appList.currentIndex = index
                            onClicked: root.launchIndex(index)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: filteredApps.values.length === 0
                    opacity: root.reveal

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰀻"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 31
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No applications found"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3
                spacing: 12

                Text {
                    text: "↑ ↓  navigate"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
                Text {
                    text: "↵  launch"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
                Text {
                    text: "esc  close"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
