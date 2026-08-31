import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// =====================================================================
// Emoji picker popup for Hyprland.
// Ported from eww.yuck's (defwidget emoji-popup) / (defwindow emoji-popup)
// + scripts/emoji.sh.
//
// What changed vs. the eww/X11 version:
//
// - Search-as-you-type: emoji.sh's `search`/`list` split existed only
//   because eww's `defpoll` command is a static string that can't read
//   an eww var directly -- so the search box wrote a term to a state
//   file on disk and a 1s poll picked it up from there. QML doesn't
//   have that limitation: `searchText` below is just a normal property
//   the search field binds to, and `filtered` is a binding that
//   recomputes instantly on every keystroke. No script, no polling,
//   no state file.
//
// - Grid layout: emoji.sh's `list` action pre-chunked matches into
//   rows of $COLS=8 in bash, because eww's `for` widget can't wrap a
//   flat list into a grid on its own. GridView wraps automatically
//   based on cellWidth, so `emojiData`/`allEmoji` below stay flat lists.
//
// - Typing the pick + focus handling: on X11, eww's popup window
//   wasn't managed by bspwm, so nothing handed it keyboard focus when
//   it appeared, and focus never automatically returned to the
//   previously-active window when it closed -- emoji.sh's `open`
//   action had to `xdotool getactivewindow` to remember that window,
//   force-focus the popup with `xdotool windowfocus`, and `pick` had
//   to `xdotool windowactivate` back to the remembered window before
//   `xdotool type`-ing into it.
//   Under Hyprland/wlroots, a layer-shell surface with on-demand
//   keyboard focus (WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand,
//   set below) behaves the
//   opposite way: it only grabs focus while visible, and the
//   compositor automatically restores focus to whatever was focused
//   before as soon as it's hidden again -- so there's no window to
//   remember or reactivate. `pick()` just hides the popup and lets
//   Hyprland do that, then types via `wtype` (Wayland's `xdotool type`
//   equivalent) after a short delay for the focus handoff to land,
//   mirroring emoji.sh's `sleep 0.05`. Needs `wtype` installed; the
//   clipboard copy (`wl-copy`, needs `wl-clipboard`) always happens
//   too, exactly as emoji.sh did with `xclip`, so the pick still lands
//   on the clipboard even if `wtype` isn't present or the target
//   app doesn't accept synthetic input.
//
// - Opening the popup: emoji.sh's `open` action was bound to `super+e`
//   in sxhkdrc, calling straight into the eww/bspwm world. Hyprland
//   binds can't call a QML function directly, so this exposes the
//   same toggle over Quickshell's IPC instead -- add to hyprland.conf:
//     bind = SUPER, E, exec, qs ipc call emoji toggle
//   (adjust `qs ipc call emoji toggle` to `qs -c <config-name> ipc
//   call emoji toggle` if quickshell isn't running as the default config).
// =====================================================================

PanelWindow {
    id: root

    // was: DATA in scripts/emoji.sh -- "emoji|keywords" per line, ported
    // 1:1 (see that script's comment: curated, not exhaustive unicode).
    readonly property string emojiData: `
😀|grinning face smile happy
😃|smile happy grin
😄|smile happy laugh
😁|grin happy smile
😆|laugh happy squint
😅|sweat smile nervous laugh
🤣|rofl rolling laughing
😂|joy tears laughing crying
🙂|slight smile
🙃|upside down smile silly
😉|wink
😊|blush smile happy
😇|angel halo innocent
🥰|love hearts smile adore
😍|heart eyes love
🤩|star struck excited
😘|kiss love
😗|kiss
😙|kiss smile
😋|yum tasty tongue
😛|tongue playful
😝|tongue squint silly
🤪|zany crazy silly
🤨|skeptical eyebrow
🧐|monocle thinking curious
🤓|nerd glasses
😎|cool sunglasses
🥸|disguise glasses
🥳|party celebrate birthday
😏|smirk
😒|unamused annoyed
😞|disappointed sad
😔|pensive sad
😟|worried
🙁|frown sad
☹️|frown sad
😣|persevere struggle
😖|confounded frustrated
😫|tired exhausted
😩|weary tired
🥺|pleading puppy eyes
😢|cry sad tear
😭|sob cry loud
😤|triumph steam angry
😠|angry mad
😡|rage furious angry
🤬|cursing swearing angry
🤯|mind blown exploding
😳|flushed embarrassed
🥵|hot heat sweating
🥶|cold freezing
😱|scream fear shocked
😨|fearful scared
😰|anxious sweat nervous
😥|sad relieved sweat
😓|sweat downcast
🤗|hug
🤔|thinking hmm
🤭|hand over mouth giggle
🤫|shush quiet secret
🤥|lying pinocchio nose
😶|no mouth speechless
😐|neutral face
😑|expressionless blank
😬|grimace awkward
🙄|eye roll
😯|surprised hushed
😮|open mouth surprised
😲|astonished shocked
🥱|yawn tired bored
😴|sleeping zzz
🤤|drool
🤐|zipper mouth quiet
🥴|woozy dizzy drunk
🤢|nauseated sick
🤮|vomit sick
🤧|sneeze sick
😷|mask sick
🤒|thermometer sick
🤕|bandage hurt
🤑|money mouth greedy rich
🤠|cowboy hat
😈|devil smiling evil
👿|devil angry
👹|ogre monster
👺|goblin monster
🤡|clown
💩|poop poo
👻|ghost
💀|skull dead
☠️|skull crossbones danger
👽|alien
👾|alien monster invader
🤖|robot bot
😺|cat smile happy
😻|cat heart love
😹|cat laugh joy
🙀|cat scream shocked
👋|wave hello bye
👋🏻|wave hello bye light skin tone tone
👋🏼|wave hello bye medium-light skin tone tone
👋🏽|wave hello bye medium skin tone tone
👋🏾|wave hello bye medium-dark skin tone tone
👋🏿|wave hello bye dark skin tone tone
🤚|raised back hand
🤚🏻|raised back hand light skin tone tone
🤚🏼|raised back hand medium-light skin tone tone
🤚🏽|raised back hand medium skin tone tone
🤚🏾|raised back hand medium-dark skin tone tone
🤚🏿|raised back hand dark skin tone tone
🖐️|hand fingers splayed
🖐️🏻|hand fingers splayed light skin tone tone
🖐️🏼|hand fingers splayed medium-light skin tone tone
🖐️🏽|hand fingers splayed medium skin tone tone
🖐️🏾|hand fingers splayed medium-dark skin tone tone
🖐️🏿|hand fingers splayed dark skin tone tone
✋|hand stop high five
✋🏻|hand stop high five light skin tone tone
✋🏼|hand stop high five medium-light skin tone tone
✋🏽|hand stop high five medium skin tone tone
✋🏾|hand stop high five medium-dark skin tone tone
✋🏿|hand stop high five dark skin tone tone
🖖|vulcan spock
🖖🏻|vulcan spock light skin tone tone
🖖🏼|vulcan spock medium-light skin tone tone
🖖🏽|vulcan spock medium skin tone tone
🖖🏾|vulcan spock medium-dark skin tone tone
🖖🏿|vulcan spock dark skin tone tone
👌|ok okay
👌🏻|ok okay light skin tone tone
👌🏼|ok okay medium-light skin tone tone
👌🏽|ok okay medium skin tone tone
👌🏾|ok okay medium-dark skin tone tone
👌🏿|ok okay dark skin tone tone
🤌|pinched fingers italian
🤌🏻|pinched fingers italian light skin tone tone
🤌🏼|pinched fingers italian medium-light skin tone tone
🤌🏽|pinched fingers italian medium skin tone tone
🤌🏾|pinched fingers italian medium-dark skin tone tone
🤌🏿|pinched fingers italian dark skin tone tone
🤏|pinch small
🤏🏻|pinch small light skin tone tone
🤏🏼|pinch small medium-light skin tone tone
🤏🏽|pinch small medium skin tone tone
🤏🏾|pinch small medium-dark skin tone tone
🤏🏿|pinch small dark skin tone tone
✌️|peace victory
🤞|fingers crossed luck
🤞🏻|fingers crossed luck light skin tone tone
🤞🏼|fingers crossed luck medium-light skin tone tone
🤞🏽|fingers crossed luck medium skin tone tone
🤞🏾|fingers crossed luck medium-dark skin tone tone
🤞🏿|fingers crossed luck dark skin tone tone
🤟|love you gesture
🤟🏻|love you gesture light skin tone tone
🤟🏼|love you gesture medium-light skin tone tone
🤟🏽|love you gesture medium skin tone tone
🤟🏾|love you gesture medium-dark skin tone tone
🤟🏿|love you gesture dark skin tone tone
🤘|rock horns
🤘🏻|rock horns light skin tone tone
🤘🏼|rock horns medium-light skin tone tone
🤘🏽|rock horns medium skin tone tone
🤘🏾|rock horns medium-dark skin tone tone
🤘🏿|rock horns dark skin tone tone
🤙|call me hang loose
🤙🏻|call me hang loose light skin tone tone
🤙🏼|call me hang loose medium-light skin tone tone
🤙🏽|call me hang loose medium skin tone tone
🤙🏾|call me hang loose medium-dark skin tone tone
🤙🏿|call me hang loose dark skin tone tone
👈|point left
👈🏻|point left light skin tone tone
👈🏼|point left medium-light skin tone tone
👈🏽|point left medium skin tone tone
👈🏾|point left medium-dark skin tone tone
👈🏿|point left dark skin tone tone
👉|point right
👉🏻|point right light skin tone tone
👉🏼|point right medium-light skin tone tone
👉🏽|point right medium skin tone tone
👉🏾|point right medium-dark skin tone tone
👉🏿|point right dark skin tone tone
👆|point up
👆🏻|point up light skin tone tone
👆🏼|point up medium-light skin tone tone
👆🏽|point up medium skin tone tone
👆🏾|point up medium-dark skin tone tone
👆🏿|point up dark skin tone tone
🖕|middle finger
🖕🏻|middle finger light skin tone tone
🖕🏼|middle finger medium-light skin tone tone
🖕🏽|middle finger medium skin tone tone
🖕🏾|middle finger medium-dark skin tone tone
🖕🏿|middle finger dark skin tone tone
👇|point down
👇🏻|point down light skin tone tone
👇🏼|point down medium-light skin tone tone
👇🏽|point down medium skin tone tone
👇🏾|point down medium-dark skin tone tone
👇🏿|point down dark skin tone tone
☝️|point up index
☝️🏻|point up index light skin tone tone
☝️🏼|point up index medium-light skin tone tone
☝️🏽|point up index medium skin tone tone
☝️🏾|point up index medium-dark skin tone tone
☝️🏿|point up index dark skin tone tone
👍|thumbs up like good
👍🏻|thumbs up like good light skin tone tone
👍🏼|thumbs up like good medium-light skin tone tone
👍🏽|thumbs up like good medium skin tone tone
👍🏾|thumbs up like good medium-dark skin tone tone
👍🏿|thumbs up like good dark skin tone tone
👎|thumbs down dislike bad
👎🏻|thumbs down dislike bad light skin tone tone
👎🏼|thumbs down dislike bad medium-light skin tone tone
👎🏽|thumbs down dislike bad medium skin tone tone
👎🏾|thumbs down dislike bad medium-dark skin tone tone
👎🏿|thumbs down dislike bad dark skin tone tone
✊|fist raised
✊🏻|fist raised light skin tone tone
✊🏼|fist raised medium-light skin tone tone
✊🏽|fist raised medium skin tone tone
✊🏾|fist raised medium-dark skin tone tone
✊🏿|fist raised dark skin tone tone
👊|fist bump punch
👊🏻|fist bump punch light skin tone tone
👊🏼|fist bump punch medium-light skin tone tone
👊🏽|fist bump punch medium skin tone tone
👊🏾|fist bump punch medium-dark skin tone tone
👊🏿|fist bump punch dark skin tone tone
🤛|fist left
🤛🏻|fist left light skin tone tone
🤛🏼|fist left medium-light skin tone tone
🤛🏽|fist left medium skin tone tone
🤛🏾|fist left medium-dark skin tone tone
🤛🏿|fist left dark skin tone tone
🤜|fist right
🤜🏻|fist right light skin tone tone
🤜🏼|fist right medium-light skin tone tone
🤜🏽|fist right medium skin tone tone
🤜🏾|fist right medium-dark skin tone tone
🤜🏿|fist right dark skin tone tone
👏|clap applause
👏🏻|clap applause light skin tone tone
👏🏼|clap applause medium-light skin tone tone
👏🏽|clap applause medium skin tone tone
👏🏾|clap applause medium-dark skin tone tone
👏🏿|clap applause dark skin tone tone
🙌|raised hands celebrate
🙌🏻|raised hands celebrate light skin tone tone
🙌🏼|raised hands celebrate medium-light skin tone tone
🙌🏽|raised hands celebrate medium skin tone tone
🙌🏾|raised hands celebrate medium-dark skin tone tone
🙌🏿|raised hands celebrate dark skin tone tone
👐|open hands
👐🏻|open hands light skin tone tone
👐🏼|open hands medium-light skin tone tone
👐🏽|open hands medium skin tone tone
👐🏾|open hands medium-dark skin tone tone
👐🏿|open hands dark skin tone tone
🤲|palms up prayer offer
🤲🏻|palms up prayer offer light skin tone tone
🤲🏼|palms up prayer offer medium-light skin tone tone
🤲🏽|palms up prayer offer medium skin tone tone
🤲🏾|palms up prayer offer medium-dark skin tone tone
🤲🏿|palms up prayer offer dark skin tone tone
🤝|handshake deal
🤝🏻|handshake deal light skin tone tone
🤝🏼|handshake deal medium-light skin tone tone
🤝🏽|handshake deal medium skin tone tone
🤝🏾|handshake deal medium-dark skin tone tone
🤝🏿|handshake deal dark skin tone tone
🙏|pray please thanks folded hands
🙏🏻|pray please thanks folded hands light skin tone tone
🙏🏼|pray please thanks folded hands medium-light skin tone tone
🙏🏽|pray please thanks folded hands medium skin tone tone
🙏🏾|pray please thanks folded hands medium-dark skin tone tone
🙏🏿|pray please thanks folded hands dark skin tone tone
💪|muscle strong flex
💪🏻|muscle strong flex light skin tone tone
💪🏼|muscle strong flex medium-light skin tone tone
💪🏽|muscle strong flex medium skin tone tone
💪🏾|muscle strong flex medium-dark skin tone tone
💪🏿|muscle strong flex dark skin tone tone
👀|eyes looking
👶|baby
👶🏻|baby light skin tone tone
👶🏼|baby medium-light skin tone tone
👶🏽|baby medium skin tone tone
👶🏾|baby medium-dark skin tone tone
👶🏿|baby dark skin tone tone
🧒|child kid
🧒🏻|child kid light skin tone tone
🧒🏼|child kid medium-light skin tone tone
🧒🏽|child kid medium skin tone tone
🧒🏾|child kid medium-dark skin tone tone
🧒🏿|child kid dark skin tone tone
👦|boy
👦🏻|boy light skin tone tone
👦🏼|boy medium-light skin tone tone
👦🏽|boy medium skin tone tone
👦🏾|boy medium-dark skin tone tone
👦🏿|boy dark skin tone tone
👧|girl
👧🏻|girl light skin tone tone
👧🏼|girl medium-light skin tone tone
👧🏽|girl medium skin tone tone
👧🏾|girl medium-dark skin tone tone
👧🏿|girl dark skin tone tone
🧑|person adult
🧑🏻|person adult light skin tone tone
🧑🏼|person adult medium-light skin tone tone
🧑🏽|person adult medium skin tone tone
🧑🏾|person adult medium-dark skin tone tone
🧑🏿|person adult dark skin tone tone
👨|man
👨🏻|man light skin tone tone
👨🏼|man medium-light skin tone tone
👨🏽|man medium skin tone tone
👨🏾|man medium-dark skin tone tone
👨🏿|man dark skin tone tone
👩|woman
👩🏻|woman light skin tone tone
👩🏼|woman medium-light skin tone tone
👩🏽|woman medium skin tone tone
👩🏾|woman medium-dark skin tone tone
👩🏿|woman dark skin tone tone
🧓|older person
🧓🏻|older person light skin tone tone
🧓🏼|older person medium-light skin tone tone
🧓🏽|older person medium skin tone tone
🧓🏾|older person medium-dark skin tone tone
🧓🏿|older person dark skin tone tone
👴|old man
👴🏻|old man light skin tone tone
👴🏼|old man medium-light skin tone tone
👴🏽|old man medium skin tone tone
👴🏾|old man medium-dark skin tone tone
👴🏿|old man dark skin tone tone
👵|old woman
👵🏻|old woman light skin tone tone
👵🏼|old woman medium-light skin tone tone
👵🏽|old woman medium skin tone tone
👵🏾|old woman medium-dark skin tone tone
👵🏿|old woman dark skin tone tone
🐶|dog puppy
🐱|cat kitten
🐭|mouse
🐹|hamster
🐰|rabbit bunny
🦊|fox
🐻|bear
🐼|panda
🐨|koala
🐯|tiger
🦁|lion
🐮|cow
🐷|pig
🐸|frog
🐵|monkey
🐔|chicken
🐧|penguin
🐦|bird
🦆|duck
🦉|owl
🦇|bat
🐺|wolf
🐴|horse
🦄|unicorn
🐝|bee
🦋|butterfly
🐛|bug caterpillar
🐌|snail
🐞|ladybug
🐢|turtle
🐍|snake
🦖|dinosaur trex
🐬|dolphin
🐳|whale
🐟|fish
🐙|octopus
🦀|crab
🍏|green apple
🍎|red apple
🍌|banana
🍉|watermelon
🍇|grapes
🍓|strawberry
🍒|cherries
🍑|peach
🥭|mango
🍍|pineapple
🥝|kiwi
🍅|tomato
🥑|avocado
🥦|broccoli
🌽|corn
🥕|carrot
🧄|garlic
🧅|onion
🥔|potato
🍞|bread
🥐|croissant
🧀|cheese
🥚|egg
🍳|fried egg cooking
🥓|bacon
🍔|burger hamburger
🍟|fries
🍕|pizza
🌭|hotdog
🌮|taco
🌯|burrito
🍜|noodles ramen
🍣|sushi
🍩|donut
🍪|cookie
🎂|cake birthday
🍰|cake slice
🍫|chocolate
🍿|popcorn
🍺|beer
🍻|cheers beer
🍷|wine
☕|coffee
🍵|tea
⚽|soccer football
🏀|basketball
🏈|american football
⚾|baseball
🎾|tennis
🏐|volleyball
🎱|8 ball pool
🏓|ping pong table tennis
🎮|video game controller
🎲|dice game
🎯|dart target
🎳|bowling
🎸|guitar music
🎹|piano music
🎺|trumpet music
🎧|headphones music
🎤|microphone sing
🎨|art paint palette
🎬|movie clapper film
📷|camera photo
📱|phone mobile
💻|laptop computer
⌨️|keyboard
🖥️|desktop computer
🖨️|printer
🔋|battery
💡|lightbulb idea
🔦|flashlight
📚|books study
📖|book open
✏️|pencil write
🖊️|pen write
📝|memo note write
📌|pin
📎|paperclip
✂️|scissors cut
🔒|lock locked
🔓|unlock open
🔑|key
🔨|hammer tool
🔧|wrench tool
⚙️|gear settings
🧰|toolbox
💰|money bag
💵|dollar money cash
💳|credit card
📈|chart up growth
📉|chart down decline
🗓️|calendar date
⏰|alarm clock
⏳|hourglass time
🚗|car
🚕|taxi
🚌|bus
🚲|bike bicycle
✈️|airplane plane travel
🚀|rocket launch space
🛸|ufo
⛵|sailboat boat
🚢|ship
🌍|earth globe world
🗺️|map
🏠|house home
🏢|office building
🏥|hospital
🏫|school
⛰️|mountain
🏖️|beach
🌋|volcano
🌙|moon
⭐|star
🌟|glowing star
☀️|sun sunny
⛅|partly cloudy weather
☁️|cloud
🌧️|rain
⛈️|storm thunder
❄️|snowflake snow
🔥|fire hot lit
💧|water droplet
🌊|wave ocean
❤️|red heart love
🧡|orange heart
💛|yellow heart
💚|green heart
💙|blue heart
💜|purple heart
🖤|black heart
🤍|white heart
🤎|brown heart
💔|broken heart heartbreak
❣️|heart exclamation
💕|two hearts love
💞|revolving hearts
💓|beating heart
💗|growing heart
💖|sparkling heart
💘|heart arrow cupid
✨|sparkles shiny
🎉|party popper celebrate
🎊|confetti celebrate
🎁|gift present
🎈|balloon
🏆|trophy win
🥇|gold medal first
🎖️|military medal
💯|100 perfect score
✅|check mark done yes
❌|cross mark no
❓|question mark
❗|exclamation mark
⚠️|warning caution
🚫|prohibited no entry
♻️|recycle
🔁|repeat loop
🔄|refresh reload sync
⬆️|arrow up
⬇️|arrow down
⬅️|arrow left
➡️|arrow right
`

    // parsed once: [{emoji, keywords}], mirrors emoji.sh's `while IFS='|'
    // read -r emoji keywords` loop over $DATA
    readonly property var allEmoji: root.emojiData
        .split("\n")
        .map(line => line.trim())
        .filter(line => line.length > 0)
        .map(line => {
            const i = line.indexOf("|");
            return { emoji: line.slice(0, i), keywords: line.slice(i + 1).toLowerCase() };
        })

    // was: emoji.sh's `[[ "$keywords" == *"$term_lc"* ]]` substring match
    property string searchText: ""
    readonly property var filtered: {
        const term = root.searchText.trim().toLowerCase();
        return term.length === 0
            ? root.allEmoji
            : root.allEmoji.filter(e => e.keywords.includes(term));
    }

    // was: emoji.sh's WIN_STATE_FILE / xdotool getactivewindow+windowfocus
    // dance -- see the header comment above for why none of that is
    // needed here.
    property bool open: false
    function toggle() {
        root.open = !root.open;
        // was: `eww update emoji-search-text=''`. Cleared on the field
        // itself (not just root.searchText) since the TextField below
        // only binds root.searchText -> its own text one-way, at init --
        // once the user types, TextField's own text wins, same as any
        // QML property that's driven both by binding and by user input.
        if (root.open) searchField.text = "";
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
    onVisibleChanged: if (visible) searchField.forceActiveFocus()

    // was: `scripts/emoji.sh pick <emoji>`
    function pick(emoji) {
        root.open = false;
        Quickshell.execDetached(["wl-copy", emoji]);
        pickTypeTimer.emojiToType = emoji;
        pickTypeTimer.start();
    }
    Timer {
        id: pickTypeTimer
        property string emojiToType: ""
        interval: 50 // was: emoji.sh's `sleep 0.05`
        onTriggered: Quickshell.execDetached(["wtype", emojiToType])
    }

    // was: emoji.sh's `open` action, bound to `super+e` in sxhkdrc.
    // See the header comment above for the matching hyprland.conf line.
    IpcHandler {
        target: "emoji"
        function toggle(): void { root.toggle() }
        function open(): void { if (!root.open) root.toggle() }
        function close(): void { if (root.open) root.open = false }
    }

    // eww: (defwindow emoji-popup :monitor 0 :geometry (geometry
    //       :x "0px" :y "0px" :width "460px" :height "500px"
    //       :anchor "center") :stacking "overlay" :focusable true)
    // PanelWindow has no direct "anchor: center" -- the usual way to
    // center a layer-shell popup is to cover the whole screen with a
    // transparent, click-through-everywhere-but-the-card window and
    // center the actual card inside it, which is what happens below.
    screen: Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:emoji-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    // eww: :focusable true -- the search box needs real keystrokes.
    // OnDemand (rather than Exclusive) so focus is only grabbed while
    // this is actually visible, which is what lets Hyprland hand focus
    // back to the previous window the instant it's hidden (see the
    // header comment above).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.centerIn: parent
        implicitWidth: 460
        opacity: root.reveal
        scale: 0.965 + 0.035 * root.reveal
        transform: Translate {
            x: 0 * (1.0 - root.reveal)
            y: 14 * (1.0 - root.reveal)
        }
        implicitHeight: 500
        radius: 14
        color: Theme.bg0
        border.color: Theme.bg1
        border.width: 1

        // eww: (label :class "emoji-title" ...) / (input :class
        // "emoji-search" ...) / (box :class "emoji-divider") / (scroll
        // ... (emoji-grid))
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: "Emoji"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                // was: :onchange "scripts/emoji.sh search {}; eww poll emojis"
                onTextChanged: root.searchText = text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                background: Rectangle {
                    radius: 8
                    color: Theme.bg1
                }
                // eww's `caret-color: #33b1ff` has no direct QML TextField
                // equivalent (would need a custom cursor delegate) --
                // skipped as a cosmetic-only difference.
                selectionColor: Theme.blue
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
                cellWidth: width / 8   // was: COLS=8 in emoji.sh
                cellHeight: 54
                model: root.filtered

                populate: Transition {
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animNormal }
                    NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animFast }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1.0; duration: Theme.animFast; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    // eww: (button :class "emoji-item" :onclick
                    // "scripts/emoji.sh pick '${emoji}'" (label :class
                    // "emoji-glyph" :text emoji))
                    Rectangle {
                        anchors.centerIn: parent
                        width: 48
                        height: 48
                        radius: 8
                        scale: cellArea.pressed ? 0.90 : (cellArea.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                        color: cellArea.containsMouse ? Theme.bg1 : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: cell.modelData.emoji
                            font.pixelSize: 24
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.pick(cell.modelData.emoji)
                        }
                    }
                }
            }
        }
    }
}
