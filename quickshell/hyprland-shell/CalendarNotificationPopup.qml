import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Combined calendar + notification-history popup opened from Bar.qml's clock.
PanelWindow {
    id: root

    property bool open: false
    property date shownMonth: new Date()

    function toggle() {
        root.open = !root.open
        if (root.open)
            root.shownMonth = new Date()
    }

    function addNotification(entry) {
        historyModel.insert(0, {
            appName: entry.appName || "Notification",
            summary: entry.summary || "",
            body: entry.body || "",
            appIcon: entry.appIcon || "",
            timestamp: entry.timestamp || new Date().toISOString()
        })

        // Keep the shell lightweight while still retaining a useful history.
        if (historyModel.count > 100)
            historyModel.remove(100, historyModel.count - 100)
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

    WlrLayershell.namespace: "quickshell:calendar-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        bottom: true
        right: true
    }

    // Clear the 60px bar and leave the same 10px gap as the other popups.
    margins {
        right: 70
        bottom: 10
    }

    // Keep the popup compact and, importantly, fixed-size.  Binding the
    // actual window size prevents notification contents / controls from
    // changing the panel geometry when history goes from empty to non-empty.
    implicitWidth: 600
    implicitHeight: 350

    ListModel {
        id: historyModel
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        opacity: root.reveal
        scale: 0.965 + 0.035 * root.reveal
        transform: Translate {
            x: 8 * (1.0 - root.reveal)
            y: 10 * (1.0 - root.reveal)
        }
        color: Theme.bg0
        border.width: 1
        border.color: Theme.bg1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ============================================================
            // Calendar
            // ============================================================
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.minimumWidth: 260
                Layout.maximumWidth: 260
                Layout.fillHeight: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.shownMonth, "MMMM yyyy")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 7
                        scale: prevArea.pressed ? 0.94 : (prevArea.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: prevArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "󰅁"
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: prevArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shownMonth = new Date(
                                root.shownMonth.getFullYear(),
                                root.shownMonth.getMonth() - 1,
                                1
                            )
                        }
                    }

                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 7
                        scale: nextArea.pressed ? 0.94 : (nextArea.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: nextArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "󰅂"
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: nextArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shownMonth = new Date(
                                root.shownMonth.getFullYear(),
                                root.shownMonth.getMonth() + 1,
                                1
                            )
                        }
                    }
                }

                DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: Qt.locale()

                    delegate: Text {
                        required property string shortName
                        text: shortName
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                MonthGrid {
                    id: monthGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    month: root.shownMonth.getMonth()
                    year: root.shownMonth.getFullYear()
                    locale: Qt.locale()

                    delegate: Rectangle {
                        required property var model

                        readonly property bool isToday:
                            model.day === new Date().getDate()
                            && model.month === new Date().getMonth()
                            && model.year === new Date().getFullYear()

                        color: isToday ? Theme.blue : "transparent"
                        radius: 8

                        Text {
                            anchors.centerIn: parent
                            text: model.day
                            color: parent.isToday
                                   ? Theme.bg0
                                   : model.month === monthGrid.month
                                     ? Theme.fg
                                     : Theme.fgDim
                            opacity: model.month === monthGrid.month ? 1.0 : 0.45
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: parent.isToday
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 9
                    color: Theme.bg1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDate(new Date(), "dddd, d MMMM")
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        Text {
                            text: Qt.formatTime(new Date(), "HH:mm")
                            color: Theme.purple
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true

                            Timer {
                                interval: 1000
                                running: root.open
                                repeat: true
                                onTriggered: parent.text = Qt.formatTime(new Date(), "HH:mm")
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.bg1
            }

            // ============================================================
            // Notification history
            // ============================================================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Text {
                        text: historyModel.count.toString()
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Rectangle {
                        implicitWidth: 54
                        implicitHeight: 26
                        radius: 7
                        opacity: historyModel.count > 0 ? 1.0 : 0.0
                        enabled: historyModel.count > 0
                        scale: clearArea.pressed ? 0.96 : (clearArea.containsMouse ? 1.03 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: clearArea.containsMouse ? Theme.bg2 : Theme.bg1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: "Clear"
                            color: clearArea.containsMouse ? Theme.pink : Theme.fgDim
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabled
                            onClicked: historyModel.clear()
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.centerIn: parent
                        visible: historyModel.count === 0
                        text: "󰂚\nNo notifications yet"
                        color: Theme.fgDim
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        lineHeight: 1.5
                    }

                    ListView {
                        id: historyView
                        anchors.fill: parent
                        visible: historyModel.count > 0
                        model: historyModel
                        spacing: 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animNormal }
                            NumberAnimation { property: "scale"; from: 0.97; to: 1.0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                        }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; to: 0.0; duration: Theme.animFast }
                            NumberAnimation { property: "scale"; to: 0.97; duration: Theme.animFast; easing.type: Easing.InCubic }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            id: historyCard
                            required property string appName
                            required property string summary
                            required property string body
                            required property string appIcon
                            required property string timestamp
                            required property int index

                            width: historyView.width - 10
                            implicitHeight: historyContent.implicitHeight + 14
                            radius: 9
                            color: Theme.bg1

                            ColumnLayout {
                                id: historyContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 7
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        radius: 7
                                        color: Theme.bg2

                                        Image {
                                            id: historyIcon
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            fillMode: Image.PreserveAspectFit
                                            // Notification.image can be an image://qsimage handle.
                                            // Those handles only live as long as the original
                                            // notification, so history deliberately uses the
                                            // stable application icon instead.
                                            source: historyCard.appIcon !== ""
                                                    && !historyCard.appIcon.startsWith("image://qsimage/")
                                                    ? Quickshell.iconPath(historyCard.appIcon)
                                                    : ""
                                            visible: source.toString() !== ""
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !historyIcon.visible
                                            text: "󰂚"
                                            color: Theme.purple
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: historyCard.appName
                                            color: Theme.purple
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: historyCard.summary
                                            visible: text !== ""
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: Qt.formatTime(new Date(historyCard.timestamp), "HH:mm")
                                        color: Theme.fgDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }

                                    Rectangle {
                                        implicitWidth: 24
                                        implicitHeight: 24
                                        radius: 6
                                        scale: deleteArea.pressed ? 0.92 : (deleteArea.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                                        color: deleteArea.containsMouse ? Theme.bg2 : "transparent"
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: deleteArea.containsMouse ? Theme.pink : Theme.fgDim
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: deleteArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: historyModel.remove(historyCard.index)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: historyCard.body
                                    visible: text !== ""
                                    color: Theme.fg
                                    opacity: 0.8
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
