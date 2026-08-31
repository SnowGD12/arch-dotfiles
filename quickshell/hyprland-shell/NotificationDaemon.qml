import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

PanelWindow {
    id: root

    // Emitted once for every incoming notification. The popup stores this
    // plain-data snapshot so history survives after the live notification
    // object is dismissed or expires.
    signal historyNotification(var entry)

    screen: Quickshell.screens[0]

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
    }

    // Notifications now appear on the left edge of the screen.
    margins {
        top: 10
        left: 10
    }

    implicitWidth: 360
    implicitHeight: notificationColumn.implicitHeight

    visible: server.trackedNotifications.values.length > 0


    // ================================================================
    // Notification daemon
    // ================================================================

    NotificationServer {
        id: server

        keepOnReload: false

        bodySupported: true
        bodyMarkupSupported: false

        actionsSupported: true
        imageSupported: true

        onNotification: notification => {
            root.historyNotification({
                appName: notification.appName || "Notification",
                summary: notification.summary || "",
                body: notification.body || "",
                appIcon: notification.appIcon || "",
                timestamp: new Date().toISOString()
            })

            // Quickshell discards notifications that aren't tracked.
            notification.tracked = true
        }
    }


    // ================================================================
    // Notification stack
    // ================================================================

    ColumnLayout {
        id: notificationColumn

        width: parent.width
        spacing: 8

        Repeater {
            model: server.trackedNotifications

            delegate: Rectangle {
                id: card

                opacity: 0.0
                scale: 0.965
                transformOrigin: Item.Left
                ParallelAnimation {
                    running: true
                    NumberAnimation {
                        target: card; property: "opacity"
                        from: 0.0; to: 1.0
                        duration: Theme.animNormal
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: card; property: "scale"
                        from: 0.965; to: 1.0
                        duration: Theme.animNormal
                        easing.type: Easing.OutCubic
                    }
                }

                required property var modelData

                readonly property var notification: modelData

                Layout.fillWidth: true

                implicitWidth: 360
                implicitHeight: cardContent.implicitHeight + 24

                radius: 12
                color: Theme.bg0

                border.width: 1
                border.color: Theme.bg1


                // ----------------------------------------------------
                // Expiration
                //
                // expireTimeout:
                //   > 0 = application's requested timeout
                //     0 = never automatically expire
                //   < 0 = daemon default
                // ----------------------------------------------------

                readonly property int timeoutMs:
                    notification.expireTimeout > 0
                    ? notification.expireTimeout * 1000
                    : 5000

                // Drives both the visible countdown ring and expiration.
                // 1.0 = full circle, 0.0 = expired.
                property real timeoutProgress: 1.0

                NumberAnimation {
                    target: card
                    property: "timeoutProgress"
                    from: 1.0
                    to: 0.0
                    duration: card.timeoutMs

                    // 0 means the app requested that it stays around.
                    running: card.notification.expireTimeout !== 0

                    onFinished: {
                        if (
                            card.notification
                            && card.notification.tracked
                        ) {
                            card.notification.expire()
                        }
                    }
                }


                // ====================================================
                // Card content
                // ====================================================

                ColumnLayout {
                    id: cardContent

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top

                        margins: 12
                    }

                    spacing: 8


                    // ------------------------------------------------
                    // Header
                    // ------------------------------------------------

                    RowLayout {
                        Layout.fillWidth: true

                        spacing: 10


                        // App icon
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36

                            radius: 8
                            color: Theme.bg1

                            Image {
                                id: appImage

                                anchors.fill: parent
                                anchors.margins: 7

                                fillMode: Image.PreserveAspectFit
                                smooth: true

                                source: {
                                    if (card.notification.image !== "")
                                        return card.notification.image

                                    if (card.notification.appIcon !== "")
                                        return Quickshell.iconPath(
                                            card.notification.appIcon
                                        )

                                    return ""
                                }

                                visible: source.toString() !== ""
                            }


                            // Fallback notification glyph
                            Text {
                                anchors.centerIn: parent

                                visible: !appImage.visible

                                text: "󰂚"

                                color: Theme.purple

                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                            }
                        }


                        // App + notification title
                        ColumnLayout {
                            Layout.fillWidth: true

                            spacing: 2

                            Text {
                                Layout.fillWidth: true

                                text:
                                    card.notification.appName
                                    || "Notification"

                                color: Theme.purple

                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: true

                                elide: Text.ElideRight
                            }


                            Text {
                                Layout.fillWidth: true

                                text: card.notification.summary

                                visible: text !== ""

                                color: Theme.fg

                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true

                                elide: Text.ElideRight
                            }
                        }


                        // Close button + circular expiration timer
                        Item {
                            implicitWidth: 30
                            implicitHeight: 30
                            scale: closeArea.pressed ? 0.90 : (closeArea.containsMouse ? 1.07 : 1.0)
                            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                            Canvas {
                                id: timeoutRing
                                anchors.fill: parent

                                visible:
                                    card.notification.expireTimeout !== 0

                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)

                                    const cx = width / 2
                                    const cy = height / 2
                                    const radius = Math.min(width, height) / 2 - 2
                                    const start = -Math.PI / 2

                                    // Faint full-circle track.
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                                    ctx.lineWidth = 2
                                    ctx.strokeStyle = Theme.bg2
                                    ctx.stroke()

                                    // Remaining-time arc.
                                    ctx.beginPath()
                                    ctx.arc(
                                        cx,
                                        cy,
                                        radius,
                                        start,
                                        start + Math.PI * 2 * card.timeoutProgress,
                                        false
                                    )
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    ctx.strokeStyle = Theme.blue
                                    ctx.stroke()
                                }

                                Connections {
                                    target: card

                                    function onTimeoutProgressChanged() {
                                        timeoutRing.requestPaint()
                                    }
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                anchors.centerIn: parent

                                radius: 6

                                color:
                                    closeArea.containsMouse
                                    ? Theme.bg1
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }


                            Text {
                                anchors.centerIn: parent

                                text: "󰅖"

                                color:
                                    closeArea.containsMouse
                                    ? Theme.pink
                                    : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }


                            MouseArea {
                                id: closeArea

                                anchors.fill: parent

                                hoverEnabled: true

                                onClicked:
                                    card.notification.dismiss()
                            }
                        }
                    }


                    // ------------------------------------------------
                    // Body
                    // ------------------------------------------------

                    Text {
                        Layout.fillWidth: true

                        visible: text !== ""

                        text: card.notification.body

                        // Prevent random notification markup from
                        // affecting the shell's formatting.
                        textFormat: Text.PlainText

                        wrapMode: Text.Wrap

                        maximumLineCount: 5
                        elide: Text.ElideRight

                        color: Theme.fgDim

                        font.family: Theme.fontFamily
                        font.pixelSize: 10

                        lineHeight: 1.15
                    }


                    // ------------------------------------------------
                    // Notification actions
                    // ------------------------------------------------

                    RowLayout {
                        Layout.fillWidth: true

                        visible:
                            card.notification.actions.length > 0

                        spacing: 6


                        Repeater {
                            model: card.notification.actions

                            delegate: Item {
                                id: actionButton

                                scale: actionArea.pressed ? 0.97 : (actionArea.containsMouse ? 1.015 : 1.0)
                                Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                                required property var modelData

                                Layout.fillWidth: true

                                implicitHeight: 28


                                Rectangle {
                                    anchors.fill: parent

                                    radius: 7

                                    color:
                                        actionArea.containsMouse
                                        ? Theme.bg2
                                        : Theme.bg1
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                }


                                Text {
                                    anchors.centerIn: parent

                                    width: parent.width - 12

                                    horizontalAlignment:
                                        Text.AlignHCenter

                                    text:
                                        actionButton.modelData.text

                                    color:
                                        actionArea.containsMouse
                                        ? Theme.blue
                                        : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    font.family:
                                        Theme.fontFamily

                                    font.pixelSize: 10
                                    font.bold: true

                                    elide: Text.ElideRight
                                }


                                MouseArea {
                                    id: actionArea

                                    anchors.fill: parent

                                    hoverEnabled: true

                                    onClicked:
                                        actionButton.modelData.invoke()
                                }
                            }
                        }
                    }


                    // ------------------------------------------------
                    // Urgency indicator
                    // ------------------------------------------------

                    Rectangle {
                        Layout.fillWidth: true

                        implicitHeight: 2
                        radius: 1

                        color: {
                            if (
                                card.notification.urgency
                                === NotificationUrgency.Critical
                            )
                                return Theme.pink

                            if (
                                card.notification.urgency
                                === NotificationUrgency.Low
                            )
                                return Theme.bg2

                            return Theme.blue
                        }
                    }
                }
            }
        }
    }
}
