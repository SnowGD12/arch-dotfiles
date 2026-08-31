import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    property bool open: false
    property bool actionsArmed: false

    property string profileBio: "Arch Linux • Hyprland"
    property string profileName: "snow"
    property string userName: "snow"
    property string hostName: ""
    property string avatarPath: ""
    property string homePath: "/home/snow"
    property int avatarRevision: 0

    property int cpuPercent: 0
    property int ramPercent: 0
    property int diskPercent: 0
    property string ramDetail: ""
    property string diskDetail: ""

    property bool playerAvailable: false
    property string playerStatus: "Stopped"
    property string playerName: ""
    property string musicArtist: "Nothing playing"
    property string musicTitle: "No active media player"
    property string musicArtUrl: ""
    property real musicPosition: 0
    property real musicDuration: 0
    property double seekIgnoreUntil: 0

    function formatMediaTime(seconds) {
        const value = Math.max(0, Math.floor(Number(seconds) || 0))
        const minutes = Math.floor(value / 60)
        const secs = value % 60
        return minutes + ":" + (secs < 10 ? "0" : "") + secs
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Number(value) || 0))
    }

    function refreshProfile() {
        if (profileProcess.running)
            return

        profileProcess.exec(["bash", "-lc", `
            user="$USER"
            [ -n "$user" ] || user="$(id -un 2>/dev/null)"
            [ -n "$user" ] || user="snow"

            # Use the actual login name for the profile label.
            name="$user"

            host="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
            [ -n "$host" ] || host="$(hostnamectl --static 2>/dev/null)"
            [ -n "$host" ] || host="$(hostname 2>/dev/null)"
            [ -n "$host" ] || host="unknown-host"

            avatar=""
            # Prefer the user-owned image so changing it from this popup takes effect
            # immediately without requiring root privileges.
            for f in "$HOME/.face" "$HOME/.face.icon" "/var/lib/AccountsService/icons/$user"; do
                if [ -r "$f" ] && [ -f "$f" ]; then
                    avatar="$f"
                    break
                fi
            done

            printf 'NAME=%s\nUSER=%s\nHOST=%s\nAVATAR=%s\nHOME=%s\n' \
                "$name" "$user" "$host" "$avatar" "$HOME"
        `])
    }

    function refreshStats() {
        if (statsProcess.running)
            return

        statsProcess.exec(["bash", "-lc", `
            cpu_line1="$(head -n1 /proc/stat)"
            sleep 0.20
            cpu_line2="$(head -n1 /proc/stat)"
            cpu="$(awk -v a="$cpu_line1" -v b="$cpu_line2" '
                BEGIN {
                    na=split(a,x,/ +/); nb=split(b,y,/ +/);
                    t1=0; t2=0;
                    for(i=2;i<=na;i++) t1+=x[i];
                    for(i=2;i<=nb;i++) t2+=y[i];
                    idle1=x[5]+x[6]; idle2=y[5]+y[6];
                    dt=t2-t1; di=idle2-idle1;
                    if(dt>0) printf "%.0f", 100*(dt-di)/dt; else print 0
                }')"
            [[ "$cpu" =~ ^[0-9]+$ ]] || cpu=0

            mem_total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
            mem_avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
            [[ "$mem_total_kb" =~ ^[0-9]+$ ]] || mem_total_kb=0
            [[ "$mem_avail_kb" =~ ^[0-9]+$ ]] || mem_avail_kb=0
            mem_used_kb=$((mem_total_kb-mem_avail_kb))
            [ "$mem_used_kb" -lt 0 ] && mem_used_kb=0
            if [ "$mem_total_kb" -gt 0 ]; then
                ram=$((100*mem_used_kb/mem_total_kb))
            else
                ram=0
            fi
            ram_used_h="$(numfmt --from-unit=1024 --to=iec-i --suffix=B "$mem_used_kb" 2>/dev/null || printf '%s KiB' "$mem_used_kb")"
            ram_total_h="$(numfmt --from-unit=1024 --to=iec-i --suffix=B "$mem_total_kb" 2>/dev/null || printf '%s KiB' "$mem_total_kb")"

            read -r disk_total disk_used disk_pct <<< "$(df -B1 --output=size,used,pcent / 2>/dev/null | tail -n1 | awk '{gsub(/%/,"",$3); print $1, $2, $3}')"
            [[ "$disk_pct" =~ ^[0-9]+$ ]] || disk_pct=0
            disk_used_h="$(numfmt --to=iec-i --suffix=B "$disk_used" 2>/dev/null || printf '%s B' "$disk_used")"
            disk_total_h="$(numfmt --to=iec-i --suffix=B "$disk_total" 2>/dev/null || printf '%s B' "$disk_total")"

            printf 'CPU=%s\nRAM=%s\nRAM_DETAIL=%s / %s\nDISK=%s\nDISK_DETAIL=%s / %s\n' \
                "$cpu" "$ram" "$ram_used_h" "$ram_total_h" \
                "$disk_pct" "$disk_used_h" "$disk_total_h"
        `])
    }

    function refreshPlayer() {
        if (playerProcess.running)
            return

        playerProcess.exec(["bash", "-lc", `
            if ! command -v playerctl >/dev/null 2>&1; then
                printf 'AVAILABLE=0\n'
                exit 0
            fi

            # Keep ordinary metadata separate from playback timing.  Some
            # players/playerctl versions do not expand mpris:length reliably
            # when it is embedded inside a custom metadata format.
            line="$(playerctl metadata --format '{{status}}\t{{playerName}}\t{{artist}}\t{{title}}\t{{mpris:artUrl}}' 2>/dev/null | head -n1)"
            if [ -z "$line" ]; then
                printf 'AVAILABLE=0\n'
                exit 0
            fi

            IFS=$'\t' read -r status player artist title art <<< "$line"

            position="$(playerctl position 2>/dev/null | head -n1)"
            length_us="$(playerctl metadata mpris:length 2>/dev/null | head -n1)"

            [ -n "$position" ] || position="0"
            [ -n "$length_us" ] || length_us="0"

            # playerctl position is already in seconds.
            position="$(awk -v p="$position" 'BEGIN {
                p += 0
                if (p < 0) p = 0
                printf "%.3f", p
            }')"

            # MPRIS length is expressed in microseconds.
            duration="$(awk -v us="$length_us" 'BEGIN {
                us += 0
                if (us < 0) us = 0
                printf "%.3f", us / 1000000
            }')"

            printf 'AVAILABLE=1\nSTATUS=%s\nPLAYER=%s\nARTIST=%s\nTITLE=%s\nART=%s\nPOSITION=%s\nDURATION=%s\n' \
                "$status" "$player" "$artist" "$title" "$art" "$position" "$duration"
        `])
    }

    function playerCommand(command) {
        Quickshell.execDetached(["playerctl", command])
        playerRefreshDelay.restart()
    }

    function seekPlayer(seconds) {
        if (!root.playerAvailable || root.musicDuration <= 0)
            return

        const target = Math.max(0, Math.min(root.musicDuration, Number(seconds) || 0))

        // Move the UI immediately. Some players report their old position (or
        // zero) briefly after a seek, so ignore position resyncs for a moment.
        root.musicPosition = target
        root.seekIgnoreUntil = Date.now() + 1500
        Quickshell.execDetached(["playerctl", "position", target.toFixed(3)])
    }

    function chooseAvatar() {
        if (avatarPickerProcess.running)
            return

        avatarPickerProcess.exec(["bash", "-lc", `
            choice=""

            if command -v zenity >/dev/null 2>&1; then
                choice="$(zenity --file-selection --title='Choose a profile picture' --filename="$HOME/Pictures/" --file-filter='Images | *.png *.jpg *.jpeg *.webp *.bmp' 2>/dev/null)"
            elif command -v kdialog >/dev/null 2>&1; then
                choice="$(kdialog --getopenfilename "$HOME/Pictures" 'Images (*.png *.jpg *.jpeg *.webp *.bmp)' 2>/dev/null)"
            elif command -v yad >/dev/null 2>&1; then
                choice="$(yad --file --title='Choose a profile picture' --filename="$HOME/Pictures/" --file-filter='Images | *.png *.jpg *.jpeg *.webp *.bmp' 2>/dev/null)"
            else
                command -v notify-send >/dev/null 2>&1 && notify-send 'Profile picture' 'Install zenity for the image picker (sudo pacman -S zenity). Opening Pictures instead.'
                if command -v thunar >/dev/null 2>&1; then
                    thunar "$HOME/Pictures" >/dev/null 2>&1 &
                elif command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "$HOME/Pictures" >/dev/null 2>&1 &
                fi
                printf 'CHANGED=0\n'
                exit 0
            fi

            if [ -n "$choice" ] && [ -f "$choice" ]; then
                cp -- "$choice" "$HOME/.face" && printf 'CHANGED=1\n'
            else
                printf 'CHANGED=0\n'
            fi
        `])
    }

    function show() {
        root.open = true
        root.refreshProfile()
        root.refreshStats()
        root.refreshPlayer()
    }

    function hide() {
        root.open = false
    }

    function toggle() {
        if (root.open)
            root.hide()
        else
            root.show()
    }

    function runAndClose(fn) {
        fn()
        root.hide()
    }

    function logoutSession() {
        Quickshell.execDetached([
            "sh", "-lc",
            "if [ -n \"$UWSM_ID\" ] && command -v uwsm >/dev/null 2>&1; then "
            + "exec uwsm stop; "
            + "elif command -v hyprshutdown >/dev/null 2>&1; then "
            + "exec hyprshutdown; "
            + "else exec hyprctl dispatch 'hl.dsp.exit()'; fi"
        ])
    }

    function parseProfile(output) {
        const lines = output.trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const sep = lines[i].indexOf("=")
            if (sep < 0)
                continue
            const key = lines[i].substring(0, sep)
            const value = lines[i].substring(sep + 1)
            if (key === "NAME") root.profileName = value || "snow"
            else if (key === "USER") root.userName = value || "snow"
            else if (key === "HOST") root.hostName = value
            else if (key === "AVATAR") root.avatarPath = value
            else if (key === "HOME") root.homePath = value || "/home/snow"
        }
    }

    function parseStats(output) {
        const lines = output.trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const sep = lines[i].indexOf("=")
            if (sep < 0)
                continue
            const key = lines[i].substring(0, sep)
            const value = lines[i].substring(sep + 1)
            if (key === "CPU") root.cpuPercent = root.clampPercent(value)
            else if (key === "RAM") root.ramPercent = root.clampPercent(value)
            else if (key === "RAM_DETAIL") root.ramDetail = value
            else if (key === "DISK") root.diskPercent = root.clampPercent(value)
            else if (key === "DISK_DETAIL") root.diskDetail = value
        }
    }

    function parsePlayer(output) {
        let available = false
        const lines = output.trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const sep = lines[i].indexOf("=")
            if (sep < 0)
                continue
            const key = lines[i].substring(0, sep)
            const value = lines[i].substring(sep + 1)
            if (key === "AVAILABLE") available = value === "1"
            else if (key === "STATUS") root.playerStatus = value
            else if (key === "PLAYER") root.playerName = value
            else if (key === "ARTIST") root.musicArtist = value || "Unknown artist"
            else if (key === "TITLE") root.musicTitle = value || "Unknown title"
            else if (key === "ART") {
                // Only change the image source when the URL actually changes.
                if (root.musicArtUrl !== value)
                    root.musicArtUrl = value
            }
            else if (key === "POSITION") {
                const p = Number(value)
                if (Date.now() >= root.seekIgnoreUntil
                        && isFinite(p)
                        && p >= 0
                        && (p > 0 || root.musicPosition < 2 || root.playerStatus !== "Playing")) {
                    root.musicPosition = p
                }
            }
            else if (key === "DURATION") {
                const d = Number(value)
                // Don't erase a known duration because of a transient MPRIS 0.
                if (isFinite(d) && d > 0)
                    root.musicDuration = d
            }
        }

        root.playerAvailable = available

        if (!available) {
            root.playerStatus = "Stopped"
            root.playerName = ""
            root.musicArtist = "Nothing playing"
            root.musicTitle = "No active media player"
            root.musicArtUrl = ""
            root.musicPosition = 0
            root.musicDuration = 0
        }
    }

    component PowerButton: Rectangle {
        id: btn
        property string icon: ""
        property string label: ""
        property color accent: Theme.purple
        signal clicked()

        implicitHeight: 48
        radius: 12
        color: btnArea.containsMouse ? Theme.bg2 : Theme.bg1
        border.width: 1
        border.color: btnArea.containsMouse ? btn.accent : Theme.bg2
        scale: btnArea.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 7

            Text {
                text: btn.icon
                color: btn.accent
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }

            Text {
                text: btn.label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
            }
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.actionsArmed
            onClicked: btn.clicked()
        }
    }

    component UsageRow: Item {
        id: metric
        property string icon: ""
        property string label: ""
        property int value: 0
        property string detail: ""
        property color accent: Theme.purple

        implicitHeight: 42

        RowLayout {
            anchors.fill: parent
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 9
                color: Theme.bg2

                Text {
                    anchors.centerIn: parent
                    text: metric.icon
                    color: metric.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: metric.label
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: metric.detail
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        text: metric.value + "%"
                        color: metric.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 5
                    radius: 3
                    color: Theme.bg2

                    Rectangle {
                        width: parent.width * (metric.value / 100.0)
                        height: parent.height
                        radius: parent.radius
                        color: metric.accent
                        Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    component MediaButton: Rectangle {
        id: mediaBtn
        property string icon: ""
        property bool primary: false
        signal clicked()

        implicitWidth: primary ? 42 : 34
        implicitHeight: primary ? 42 : 34
        radius: width / 2
        color: mediaArea.containsMouse ? (primary ? Theme.purple : Theme.bg2) : (primary ? Theme.bg2 : "transparent")
        border.width: primary ? 1 : 0
        border.color: Theme.purple
        opacity: root.playerAvailable ? 1.0 : 0.35
        scale: mediaArea.pressed ? 0.91 : 1.0

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: mediaBtn.icon
            color: primary && mediaArea.containsMouse ? Theme.bg0 : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: primary ? 18 : 15
        }

        MouseArea {
            id: mediaArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.playerAvailable
            onClicked: mediaBtn.clicked()
        }
    }

    Process {
        id: avatarPickerProcess
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("CHANGED=1") !== -1) {
                    root.avatarPath = (root.homePath || "/home/snow") + "/.face"
                    avatarReloadTimer.restart()
                }
            }
        }
    }

    Timer {
        id: avatarReloadTimer
        interval: 250
        repeat: false
        onTriggered: {
            root.avatarRevision += 1
            root.refreshProfile()
        }
    }

    Timer {
        id: actionArmTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.open)
                root.actionsArmed = true
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.open
        triggeredOnStart: false
        onTriggered: root.refreshStats()
    }

    // Slow MPRIS resync for song changes, metadata and drift.
    Timer {
        interval: 4000
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: root.refreshPlayer()
    }

    // Advance the timeline locally. This avoids spawning playerctl every
    // second and prevents seek responses from making the clock jump to 0:00.
    Timer {
        interval: 250
        repeat: true
        running: root.open && root.playerAvailable && root.playerStatus === "Playing"
        onTriggered: {
            if (root.musicDuration > 0) {
                root.musicPosition = Math.min(
                    root.musicDuration,
                    root.musicPosition + interval / 1000.0
                )
            }
        }
    }

    Timer {
        id: playerRefreshDelay
        interval: 250
        repeat: false
        onTriggered: root.refreshPlayer()
    }

    onOpenChanged: {
        root.actionsArmed = false
        actionArmTimer.stop()
        if (root.open)
            actionArmTimer.start()
    }

    Process {
        id: profileProcess
        stdout: StdioCollector { onStreamFinished: root.parseProfile(text) }
    }

    Process {
        id: statsProcess
        stdout: StdioCollector { onStreamFinished: root.parseStats(text) }
    }

    Process {
        id: playerProcess
        stdout: StdioCollector { onStreamFinished: root.parsePlayer(text) }
    }

    property real reveal: root.open ? 1.0 : 0.0
    Behavior on reveal {
        NumberAnimation {
            duration: root.open ? Theme.animNormal : Theme.animFast
            easing.type: root.open ? Easing.OutCubic : Easing.InCubic
        }
    }

    visible: root.open || root.reveal > 0.001

    HyprlandFocusGrab {
        id: outsideClickGrab
        windows: [root]
        active: root.open
        onCleared: {
            if (root.open)
                root.hide()
        }
    }

    screen: Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:power-profile"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }

    margins {
        right: 70
        top: 10
    }

    implicitWidth: 390
    implicitHeight: content.implicitHeight + 24

    Rectangle {
        anchors.fill: parent
        opacity: root.reveal
        scale: 0.975 + 0.025 * root.reveal
        transform: Translate {
            x: 14 * (1.0 - root.reveal)
            y: -4 * (1.0 - root.reveal)
        }
        radius: 18
        color: Theme.bg0
        border.width: 1
        border.color: Theme.bg2

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 108
                radius: 15
                color: Theme.bg1
                border.width: 1
                border.color: Theme.bg2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        id: avatarFrame
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 72
                        // 72x72 -> radius 36 makes the profile picture perfectly circular.
                        radius: 36
                        color: Theme.bg2
                        border.width: 1
                        border.color: avatarArea.containsMouse ? Theme.pink : Theme.purple
                        clip: true
                        scale: avatarArea.pressed ? 0.96 : (avatarArea.containsMouse ? 1.03 : 1.0)

                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: root.avatarPath.length > 0
                                    ? ("file://" + root.avatarPath + "?v=" + root.avatarRevision)
                                    : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: avatarImage
                            visible: avatarImage.status === Image.Ready

                            maskSource: Rectangle {
                                width: avatarFrame.width
                                height: avatarFrame.height
                                radius: width / 2
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImage.status !== Image.Ready
                            text: "󰀄"
                            color: Theme.purple
                            font.family: Theme.fontFamily
                            font.pixelSize: 32
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: avatarArea.containsMouse
                            color: "#66000000"

                            Text {
                                anchors.centerIn: parent
                                text: "󰏫"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 22
                            }
                        }

                        MouseArea {
                            id: avatarArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            // Prevent rapid clicks used to close/reopen the power menu
                            // from falling through to the profile-picture picker.
                            // actionsArmed is reset immediately when the popup closes
                            // and only becomes true 400 ms after it opens.
                            enabled: root.actionsArmed
                            onClicked: {
                                if (root.actionsArmed)
                                    root.chooseAvatar()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: root.profileName || "snow"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 19
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                implicitWidth: 58
                                implicitHeight: 22
                                radius: 11
                                color: Theme.bg2

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰣇  ARCH"
                                    color: Theme.purple
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    font.bold: true
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.profileBio
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Item { Layout.preferredHeight: 3 }

                        Text {
                            Layout.fillWidth: true
                            text: "󰒋  " + (root.hostName || "host")
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "@" + (root.userName || "snow")
                            color: Theme.purple
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: usageColumn.implicitHeight + 20
                radius: 15
                color: Theme.bg1
                border.width: 1
                border.color: Theme.bg2

                ColumnLayout {
                    id: usageColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "SYSTEM"
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                            font.letterSpacing: 1.2
                        }
                        Text {
                            text: "LIVE"
                            color: Theme.purple
                            opacity: 0.85
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }

                    UsageRow {
                        Layout.fillWidth: true
                        icon: "󰻠"
                        label: "CPU"
                        value: root.cpuPercent
                        accent: Theme.purple
                    }

                    UsageRow {
                        Layout.fillWidth: true
                        icon: "󰍛"
                        label: "Memory"
                        value: root.ramPercent
                        detail: root.ramDetail
                        accent: Theme.blue
                    }

                    UsageRow {
                        Layout.fillWidth: true
                        icon: "󰋊"
                        label: "Root disk"
                        value: root.diskPercent
                        detail: root.diskDetail
                        accent: Theme.pink
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 137
                radius: 15
                color: Theme.bg1
                border.width: 1
                border.color: Theme.bg2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 11

                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 90
                        radius: 13
                        color: Theme.bg2
                        clip: true

                        Image {
                            id: coverImage
                            anchors.fill: parent
                            source: root.playerAvailable ? root.musicArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: coverImage
                            visible: coverImage.status === Image.Ready

                            maskSource: Rectangle {
                                width: 90
                                height: 90
                                radius: 13
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: coverImage.status !== Image.Ready
                            color: Theme.bg2

                            Text {
                                anchors.centerIn: parent
                                text: root.playerAvailable ? "󰎆" : "󰝚"
                                color: Theme.purple
                                font.family: Theme.fontFamily
                                font.pixelSize: 30
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                Layout.fillWidth: true
                                text: root.playerAvailable ? "NOW PLAYING" : "MEDIA"
                                color: Theme.purple
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                font.bold: true
                                font.letterSpacing: 1.0
                            }

                            Text {
                                visible: root.playerName.length > 0
                                text: root.playerName
                                color: Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.musicTitle
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.musicArtist
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12

                            MediaButton {
                                icon: "󰒮"
                                onClicked: root.playerCommand("previous")
                            }

                            MediaButton {
                                primary: true
                                icon: root.playerStatus === "Playing" ? "󰏤" : "󰐊"
                                onClicked: root.playerCommand("play-pause")
                            }

                            MediaButton {
                                icon: "󰒭"
                                onClicked: root.playerCommand("next")
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "POWER"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 1.2
                }

                Text {
                    text: root.userName + "@" + root.hostName
                    color: Theme.fgDim
                    opacity: 0.55
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                PowerButton {
                    Layout.fillWidth: true
                    icon: "󰐥"
                    label: "Shutdown"
                    accent: Theme.pink
                    onClicked: root.runAndClose(() => Quickshell.execDetached(["systemctl", "poweroff"]))
                }

                PowerButton {
                    Layout.fillWidth: true
                    icon: "󰜉"
                    label: "Reboot"
                    accent: Theme.purple
                    onClicked: root.runAndClose(() => Quickshell.execDetached(["systemctl", "reboot"]))
                }

                PowerButton {
                    Layout.fillWidth: true
                    icon: "󰤄"
                    label: "Suspend"
                    accent: Theme.blue
                    onClicked: root.runAndClose(() => Quickshell.execDetached(["systemctl", "suspend"]))
                }

                PowerButton {
                    Layout.fillWidth: true
                    icon: "󰍃"
                    label: "Logout"
                    accent: Theme.purple
                    onClicked: root.runAndClose(() => root.logoutSession())
                }
            }
        }
    }
}
