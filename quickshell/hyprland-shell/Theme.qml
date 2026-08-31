pragma Singleton
import QtQuick

// ---------- Oxocarbon palette (ported 1:1 from eww/eww.scss) ----------
QtObject {
    readonly property color bg0: "#161616"     // base background
    readonly property color bg1: "#262626"     // panel / trough / hover background
    readonly property color bg2: "#393939"     // subtle borders / inactive fill
    readonly property color fg: "#f2f4f8"       // primary text
    readonly property color fgDim: "#525252"    // muted / free / inactive text
    readonly property color blue: "#33b1ff"     // primary accent (focused workspace, slider fill)
    readonly property color purple: "#be95ff"   // secondary accent (logo)
    readonly property color pink: "#ff7eb6"     // urgent / warning accent

    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property int barWidth: 60
    readonly property int exclusiveZone: 60

    // Shared motion timings. Keep these short so the shell feels responsive.
    readonly property int animFast: 110
    readonly property int animNormal: 180
    readonly property int animSlow: 260
}
