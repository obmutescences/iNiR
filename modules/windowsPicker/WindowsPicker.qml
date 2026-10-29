pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.iris.style
import "PickerMath.js" as M

Scope {
    id: root

    // ---- configuration ------------------------------------------------
    readonly property var conf: Config.options?.windowsPicker ?? ({})
    readonly property bool enabled: conf.enable ?? true
    readonly property string appearanceSetting: {
        const value = String(conf.appearance ?? "fly")
        return ["fly", "slide_up", "zoom_rotate", "flip", "unfold", "random"].includes(value) ? value : "fly"
    }
    readonly property string gatherSetting: {
        const value = String(conf.gather ?? "cascade")
        return ["cascade", "circular", "random", "wave"].includes(value) ? value : "cascade"
    }
    readonly property string cardSizeSetting: {
        const value = String(conf.cardSize ?? "auto")
        return ["auto", "compact", "large"].includes(value) ? value : "auto"
    }
    readonly property string panelMode: {
        const value = String(conf.panel ?? "none")
        return ["none", "late", "sync"].includes(value) ? value : "none"
    }
    readonly property var letters: M.normalizeLetters(conf.letters ?? "asdfghjkl")
    function cardMaxFor(screen): int {
        if (root.cardSizeSetting === "compact")
            return 220
        if (root.cardSizeSetting === "large")
            return 380
        return Math.round(M.clamp(screen.width * 0.16, 260, 420) * 0.9)
    }

    // ---- state --------------------------------------------------------
    property bool shown: false
    property bool closing: false
    property int phase: 0                // 1 entering, 2 exiting
    property real clock: 0
    property int entryMaxDelay: 0
    property string resolvedAppearance: "fly"
    property var cards: []
    property var layoutInfo: ({})
    property string prefix: ""
    property int focusId: -1
    property int activationId: -1
    property string targetOutput: ""

    readonly property bool animations: Appearance.animationsEnabled

    // ---- palette ------------------------------------------------------
    readonly property color wallpaperColor: Appearance.wallpaperDominantColor
    readonly property real hue: wallpaperColor.hslHue
    readonly property real saturation: Math.max(0.20, Math.min(0.40, wallpaperColor.hslSaturation))
    // Card body: the wallpaper primary at a fixed, low lightness. The info bar
    // is part of the body, so this is also the bar colour.
    readonly property color wpPrimary: Qt.hsla(hue, saturation, 0.30, 1.0)
    readonly property color wpPrimaryHover: Qt.hsla(hue, saturation, 0.36, 1.0)
    readonly property color wpPrimaryStrong: Qt.hsla(hue, saturation, 0.42, 1.0)
    // Focus ring, glow and header accents: the primary hue, saturated enough
    // to read as colour rather than white on a dark ground.
    readonly property color wpAccent: Qt.hsla(hue, Math.max(0.38, saturation), 0.62, 1.0)
    // Text: the same highlight the centre panel's memory figure uses.
    readonly property color wpInk: IrisStyle.secondaryAccent

    // ---- lifecycle ----------------------------------------------------
    function toggle(): void {
        if (root.shown)
            root.close()
        else
            root.open()
    }

    function open(): void {
        if (!root.enabled || root.shown)
            return

        const screenName = String(GlobalStates.focusedScreen?.name ?? NiriService.currentOutput ?? "")
        const screens = Quickshell.screens
        const screen = screens.find(item => item.name === screenName) ?? screens[0]
        if (!screen)
            return

        const pool = ["fly", "slide_up", "zoom_rotate", "flip", "unfold"]
        root.resolvedAppearance = root.appearanceSetting === "random"
            ? pool[Math.floor(Math.random() * pool.length)]
            : root.appearanceSetting
        root.targetOutput = screen.name
        root.prefix = ""
        root.focusId = -1
        root.activationId = -1
        root.closing = false
        root.phase = 0
        root.clock = 0

        const built = root.buildCards(screen)
        if (built.length === 0)
            return

        root.cards = built
        root.shown = true
        if (root.animations)
            Qt.callLater(root.startEntry)
        else
            root.startEntry()
    }

    function startEntry(): void {
        if (!root.shown || root.closing)
            return
        const duration = M.modeParams(root.resolvedAppearance).duration
        root.entryMaxDelay = root.cards.reduce((max, item) => Math.max(max, Number(item.delay ?? 0)), 0)
        root.totalMs = Math.max(1, root.entryMaxDelay + duration)
        root.phase = 1
        if (!root.animations) {
            root.clock = root.totalMs
            return
        }
        root.clock = 0
        entryAnimation.from = 0
        entryAnimation.to = root.totalMs
        entryAnimation.duration = root.totalMs
        entryAnimation.restart()
    }

    property int totalMs: 1

    function close(): void {
        if (!root.shown || root.closing)
            return
        root.closing = true
        root.prefix = ""
        prefixTimer.stop()
        if (!root.animations) {
            root.finishClose()
            return
        }
        root.phase = 2
        root.clock = 0
        const total = root.entryMaxDelay + 460
        exitAnimation.from = 0
        exitAnimation.to = total
        exitAnimation.duration = total
        exitAnimation.restart()
    }

    function finishClose(): void {
        root.shown = false
        root.closing = false
        root.phase = 0
        root.clock = 0
        root.cards = []
        root.layoutInfo = ({})
        root.focusId = -1
        root.activationId = -1
        root.prefix = ""
        root.targetOutput = ""
    }

    function requestActivate(windowId): void {
        if (!root.shown || root.closing || windowId <= 0)
            return
        root.focusId = windowId
        root.activationId = windowId
        activationTimer.restart()
    }

    // ---- snapshot -----------------------------------------------------
    function buildCards(screen): var {
        const allWindows = NiriService.windows ?? []
        const workspaces = NiriService.workspaces ?? ({})
        const scoped = allWindows.filter(item => workspaces[item.workspace_id]?.output === screen.name)
        if (scoped.length === 0)
            return []

        const sorted = scoped.slice().sort((a, b) => {
            const wsA = workspaces[a.workspace_id]
            const wsB = workspaces[b.workspace_id]
            if ((wsA?.idx ?? 0) !== (wsB?.idx ?? 0))
                return (wsA?.idx ?? 0) - (wsB?.idx ?? 0)
            const posA = a.layout?.pos_in_scrolling_layout ?? [0, 0]
            const posB = b.layout?.pos_in_scrolling_layout ?? [0, 0]
            if (posA[0] !== posB[0])
                return posA[0] - posB[0]
            return posA[1] - posB[1]
        })

        const layout = M.layoutCards(sorted.length, screen.width, screen.height, {
            cardMax: root.cardMaxFor(screen),
            cardMin: 140,
            barHeight: 46,
            gapX: 24,
            gapY: 44
        })
        const delays = M.gatherDelays(sorted.length, layout.columns, root.gatherSetting, layout.rows)
        const codes = M.assignCodes(sorted.length, root.letters)

        const focused = allWindows.find(item => item.is_focused)
        const focusedWorkspaceId = focused?.workspace_id ?? -1
        const focusedColumn = focused?.layout?.pos_in_scrolling_layout?.[0] ?? 1

        const windowsByWorkspace = ({})
        for (const item of sorted) {
            if (!windowsByWorkspace[item.workspace_id])
                windowsByWorkspace[item.workspace_id] = []
            windowsByWorkspace[item.workspace_id].push(item)
        }

        const result = []
        for (let i = 0; i < sorted.length; ++i) {
            const windowData = sorted[i]
            const slot = layout.slots[i]
            const start = M.windowStartRect(
                windowData,
                windowsByWorkspace[windowData.workspace_id] ?? [],
                screen.width,
                screen.height,
                windowData.workspace_id === focusedWorkspaceId ? focusedColumn : 1)
            result.push({
                id: windowData.id,
                title: windowData.title ?? "",
                appId: windowData.app_id ?? "",
                code: codes[i] ?? "",
                x: slot.x,
                y: slot.y,
                w: slot.w,
                h: slot.h,
                delay: delays[i] ?? 0,
                tx: start.x - (layout.areaX + slot.x),
                ty: start.y - (layout.areaY + slot.y),
                sx: slot.w > 0 ? start.w / slot.w : 1,
                sy: slot.h > 0 ? start.h / slot.h : 1

            })
        }

        // The window that already has focus starts highlighted, so the picker
        // opens onto the current window instead of an empty selection.
        root.focusId = focused?.id ?? -1
        root.layoutInfo = layout
        root.entryMaxDelay = delays.reduce((max, value) => Math.max(max, value), 0)
        // Refresh stale previews in the background; the cards show the cache at once.
        if (result.length > 0)
            WindowPreviewService.captureForTaskView(result.map(item => item.id), 15000)
        return result
    }

    // ---- keyboard -----------------------------------------------------
    function handleKey(event): bool {
        if (event.key === Qt.Key_Escape) {
            if (root.prefix.length > 0) {
                root.prefix = ""
                prefixTimer.stop()
            } else {
                root.close()
            }
            return true
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.focusId > 0)
                root.requestActivate(root.focusId)
            return true
        }

        const text = String(event.text ?? "").toUpperCase()
        if (text.length !== 1 || text < "A" || text > "Z" || !root.letters.includes(text))
            return false

        const singleLetter = root.cards.length <= root.letters.length
        if (singleLetter) {
            const match = root.cards.find(item => item.code === text)
            if (match)
                root.requestActivate(match.id)
            return true
        }

        if (root.prefix.length === 0) {
            if (root.cards.some(item => String(item.code).startsWith(text))) {
                root.prefix = text
                prefixTimer.restart()
            }
            return true
        }

        const code = root.prefix + text
        const match = root.cards.find(item => item.code === code)
        if (match) {
            prefixTimer.stop()
            root.prefix = ""
            root.requestActivate(match.id)
        } else {
            root.prefix = ""
            prefixTimer.stop()
        }
        return true
    }

    Timer {
        id: prefixTimer
        interval: 800
        repeat: false
        onTriggered: root.prefix = ""
    }

    Timer {
        id: activationTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (root.activationId > 0)
                NiriService.focusWindow(root.activationId)
            root.close()
        }
    }

    NumberAnimation {
        id: entryAnimation
        target: root
        property: "clock"
        easing.type: Easing.Linear
        onFinished: {
            if (root.phase === 1)
                root.clock = root.totalMs
        }
    }

    NumberAnimation {
        id: exitAnimation
        target: root
        property: "clock"
        easing.type: Easing.Linear
        onFinished: {
            if (root.phase === 2)
                root.finishClose()
        }
    }

    // ---- IPC ----------------------------------------------------------
    IpcHandler {
        target: "windowsPicker"

        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function status(): string {
            return JSON.stringify({
                open: root.shown,
                output: root.targetOutput,
                appearance: root.resolvedAppearance,
                cards: root.cards.length,
                focusId: root.focusId,
                prefix: root.prefix
            })
        }
    }

    // ---- surfaces -----------------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            readonly property bool isTarget: modelData.name === root.targetOutput
            readonly property var info: root.layoutInfo

            screen: modelData
            visible: root.shown && panel.isTarget

            function ensureFocusVisible(): void {
                if (!root.shown || root.focusId <= 0)
                    return
                const item = root.cards.find(entry => Number(entry.id) === Number(root.focusId))
                if (!item)
                    return
                const top = Number(item.y ?? 0)
                const bottom = top + Number(item.h ?? 0)
                const maxY = Math.max(0, scroller.contentHeight - scroller.height)
                if (top < scroller.contentY)
                    scroller.contentY = Math.max(0, top - 16)
                else if (bottom > scroller.contentY + scroller.height)
                    scroller.contentY = Math.min(maxY, bottom - scroller.height + 16)
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "quickshell:windowsPicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.shown && panel.isTarget)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Item {
                id: backdrop
                anchors.fill: parent
                opacity: root.shown && !root.closing ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: root.closing ? 280 : 200; easing.type: Easing.OutQuad }
                }

                Image {
                    anchors.fill: parent
                    source: Wallpapers.effectiveWallpaperUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.85
                        blurMax: 64
                        saturation: 1.1
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(20 / 255, 28 / 255, 41 / 255, 0.52) }
                        GradientStop { position: 1; color: Qt.rgba(8 / 255, 11 / 255, 17 / 255, 0.74) }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Item {
                id: keyboardSink
                anchors.fill: parent
                focus: root.shown && panel.isTarget
                Keys.enabled: root.shown && panel.isTarget
                Keys.onPressed: event => {
                    if (root.handleKey(event))
                        event.accepted = true
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: panel.info.marginY ?? 32
                text: "Windows " + root.cards.length
                color: root.wpAccent
                font.family: Appearance.font.family.title
                font.pixelSize: 22
                font.weight: Font.DemiBold
                opacity: {
                    if (root.panelMode === "none")
                        return 1
                    if (root.phase === 2)
                        return root.panelMode === "late" ? 0 : M.clamp(1 - root.clock / 280, 0, 1)
                    if (root.panelMode === "late")
                        return M.clamp((root.clock - 340) / 140, 0, 1)
                    return M.clamp(root.clock / 280, 0, 1)
                }
            }

            Connections {
                target: root
                function onFocusIdChanged(): void { panel.ensureFocusVisible() }
                function onShownChanged(): void {
                    if (root.shown)
                        Qt.callLater(panel.ensureFocusVisible)
                }
            }

            Flickable {
                id: scroller
                x: panel.info.areaX ?? 40
                y: panel.info.areaY ?? 90
                width: panel.info.areaW ?? width
                height: panel.info.areaH ?? 400
                contentWidth: width
                contentHeight: Math.max(height, panel.info.contentHeight ?? height)
                interactive: false
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                WheelHandler {
                    onWheel: wheel => {
                        scroller.contentY = M.clamp(scroller.contentY - wheel.angleDelta.y,
                            0, Math.max(0, scroller.contentHeight - scroller.height))
                    }
                }

                Repeater {
                    model: root.cards

                    WindowCard {
                        required property var modelData
                        cardData: modelData
                        phase: root.phase
                        clock: root.clock
                        mode: root.resolvedAppearance
                        prefix: root.prefix
                        focused: root.focusId === Number(modelData.id)
                        animationsEnabled: root.animations
                        wpPrimary: root.wpPrimary
                        wpPrimaryHover: root.wpPrimaryHover
                        wpPrimaryStrong: root.wpPrimaryStrong
                        wpAccent: root.wpAccent
                        wpInk: root.wpInk
                        visible: root.shown
                        onActivated: windowId => root.requestActivate(windowId)
                    }
                }
            }
        }
    }
}
