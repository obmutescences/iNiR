pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.iris.style
import qs.modules.iris.frame
import qs.modules.iris.components
import qs.modules.iris.field as Field

/**
 * Centered command panel: a 1120x720 glass body in the middle of the
 * focused output. Same open/close lifecycle as the Dashboard, but it belongs
 * to the iRiS family, so its glass, ink and motion come from IrisStyle.
 */
PanelWindow {
    id: root

    property bool shown: false
    // 0 = fully closed pose, 1 = resting pose. One pass drives both directions so a
    // close can take a different path than the open (drop falls through, it does not rewind).
    property real progress: 0
    // A drop comes from above when opening and leaves downwards when closing. The
    // side is kept through an interrupted move so the pose never jumps across the body.
    property real dropSide: -1
    property bool settled: false
    // The book's pitch: +78 lies flat on the side it stands from, 0 is upright.
    property real unfoldAngle: 78
    // A cold open has to let the surface map and draw once before the move starts.
    property bool warming: false
    property bool launched: false
    property int launchFrames: 0
    readonly property bool open: GlobalStates.centerPanelOpen

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080
    readonly property real widthRatio: Math.max(0.2, Math.min(0.9,
        Number(Config.options?.centerPanel?.widthRatio ?? 0.4667)))
    readonly property real heightRatio: Math.max(0.25, Math.min(0.9,
        Number(Config.options?.centerPanel?.heightRatio ?? 0.5333)))
    // The layout keeps its 1120x720 proportions and is scaled as a whole, so
    // shrinking the window shrinks the type and spacing with it.
    readonly property real contentScale: Math.max(0.3, Math.min(1, root.widthRatio / 0.5833))
    readonly property real edge: Math.max(16, IrisFrame.band + Math.round(16 * IrisStyle.density))
    readonly property real panelWidth: Math.min(root.screenWidth - root.edge * 2,
        Math.round(root.screenWidth * root.widthRatio))
    readonly property real panelHeight: Math.min(root.screenHeight - root.edge * 2,
        Math.round(root.screenHeight * root.heightRatio))
    readonly property real radius: IrisStyle.radiusPanel

    // centerPanel.animation: fade (the family's settle-in), spin, unfold, drop, aperture.
    // Qt Quick projects the rotations flat, so these are pseudo-3D poses on the body itself.
    readonly property string animationName: {
        const name = String(Config.options?.centerPanel?.animation ?? "fade")
        return ["fade", "spin", "unfold", "drop", "aperture"].includes(name) ? name : "fade"
    }
    readonly property bool motion: IrisStyle.motionEnabled
    readonly property int openDuration: !root.motion ? 0 : Math.round(IrisStyle.settleDuration
        * (root.animationName === "unfold" ? 1.3 : root.animationName === "drop" ? 1.05 : 1))
    readonly property int closeDuration: !root.motion ? 0 : Math.round(IrisStyle.settleDuration
        * (root.animationName === "unfold" ? 0.85 : root.animationName === "drop" ? 0.6 : 0.72))
    readonly property int openEasing: root.animationName === "drop" ? Easing.OutBack
        : root.animationName === "aperture" ? Easing.OutQuint
        : root.animationName === "unfold" ? Easing.InOutCubic : Easing.BezierSpline
    readonly property int closeEasing: root.animationName === "drop" || root.animationName === "aperture"
        || root.animationName === "unfold" ? Easing.InCubic : Easing.BezierSpline
    // Clamped copy for the poses that must not overshoot; the drop lift reads progress raw.
    readonly property real revealT: Math.max(0, Math.min(1, root.progress))
    // Just past the edge: the whole body is off-screen at the start and at the end of a drop.
    readonly property real dropTravel: root.screenHeight / 2 + root.panelHeight / 2
    readonly property real lift: {
        if (root.animationName === "drop") return root.dropSide * root.dropTravel * (1 - root.progress)
        if (root.animationName === "fade") return Math.round(18 * IrisStyle.density) * (1 - root.revealT)
        return 0
    }
    readonly property real bodyScale: root.animationName === "spin" ? 0.24 + 0.76 * root.revealT
        : root.animationName === "fade" ? 0.96 + 0.04 * root.revealT : 1
    readonly property real bodyScaleX: root.animationName === "aperture" ? 0.82 + 0.18 * root.revealT : 1
    readonly property real bodyScaleY: root.animationName === "aperture" ? 0.02 + 0.98 * root.revealT : 1
    readonly property real bodySpin: root.animationName === "spin" ? -100 * (1 - root.revealT) : 0
    // unfold: flat on the table, bottom edge fixed, the top edge stands up from the far side.
    readonly property real bodyTilt: root.animationName === "unfold" ? root.unfoldAngle : 0
    readonly property real bodyOpacity: root.warming ? 0.04
        : root.animationName === "aperture" || root.animationName === "unfold" ? Math.min(1, root.revealT * 2.5)
        : root.animationName === "drop" ? Math.min(1, root.revealT * 3)
        : root.revealT

    visible: root.shown
    screen: outputHold.output
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:iris-center-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IrisOutputHold {
        id: outputHold
        wanted: GlobalStates.focusedScreen
        live: root.visible
    }

    // Niri blurs exactly the body's rounded rect; the tint above it is what
    // keeps the panel readable when compositor blur is not available.
    Field.IrisBlurRegion {
        window: root
        windowWidth: root.width
        windowHeight: root.height
        shapes: root.shown && root.settled
            ? [{
                x: body.x,
                y: body.y,
                width: body.width,
                height: body.height,
                radius: body.radius,
                paints: true,
                id: "center-panel",
                glass: IrisStyle.surfaceGlass("panels")
            }]
            : []
    }

    MouseArea {
        x: 0
        y: 0
        width: parent.width
        height: parent.height
        z: 0
        onClicked: root.hide()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.open
        onActivated: root.hide()
    }
    Shortcut {
        sequence: "Tab"
        enabled: root.open
        onActivated: GlobalStates.centerPanelTab = (GlobalStates.centerPanelTab + 1) % 6
    }
    Shortcut {
        sequence: "Shift+Tab"
        enabled: root.open
        onActivated: GlobalStates.centerPanelTab = (GlobalStates.centerPanelTab + 5) % 6
    }

    Item {
        id: body

        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        z: 1
        clip: true
        readonly property real radius: root.radius

        opacity: root.bodyOpacity
        scale: root.bodyScale
        rotation: root.bodySpin
        transformOrigin: Item.Center
        transform: [
            // unfold: the bottom edge stays on the table while the body stands up from flat.
            Rotation {
                axis { x: 1; y: 0; z: 0 }
                angle: root.bodyTilt
                origin.x: body.width / 2
                origin.y: body.height
            },
            // aperture: a slit at the centre opening to the full body.
            Scale {
                xScale: root.bodyScaleX
                yScale: root.bodyScaleY
                origin.x: body.width / 2
                origin.y: body.height / 2
            },
            Translate { y: root.lift }
        ]

        ClippingRectangle {
            anchors.fill: parent
            radius: body.radius

            Loader {
                anchors.fill: parent
                active: IrisStyle.glassWallpaper
                sourceComponent: IrisGlassPane {
                    sceneOffset: Qt.point(body.x, body.y)
                    windowOffset: Qt.point(0, 0)
                    live: root.progress > 0
                    tint: "transparent"
                }
            }

            // A neutral scrim only: the blur stays the wallpaper, the ink stays readable.
            Rectangle {
                anchors.fill: parent
                visible: IrisStyle.glassWallpaper
                color: Qt.rgba(0, 0, 0, 0.60)
            }

            Rectangle {
                anchors.fill: parent
                visible: !IrisStyle.glassWallpaper
                color: IrisStyle.bodySurface
            }
        }

        IrisGlassEdge {
            anchors.fill: parent
            radius: body.radius
        }

        // Clicks inside the panel must not reach the backdrop closer.
        MouseArea {
            anchors.fill: parent
        }

        Loader {
            id: content
            width: body.width / root.contentScale - Math.round(44 * IrisStyle.density)
            height: body.height / root.contentScale - Math.round(44 * IrisStyle.density)
            anchors.centerIn: parent
            scale: root.contentScale
            transformOrigin: Item.Center
            visible: root.shown
            source: "CenterPanelContent.qml"
            onStatusChanged: if (status === Loader.Error) console.error("[CenterPanel] content failed to load")
        }
    }

    // The move itself: one value, driven in both directions. The poses above read it.
    NumberAnimation {
        id: reveal
        target: root
        property: "progress"
        onFinished: {
            if (root.progress >= 0.999) {
                root.settled = true
                return
            }
            if (root.open) return
            root.settled = false
            root.shown = false
        }
    }

    // The book is driven separately from progress so an interrupted move can be caught
    // at its current pitch instead of snapping between the two poses.
    NumberAnimation {
        id: unfoldMove
        target: root
        property: "unfoldAngle"
    }

    // A cold open is built inside an unmapped surface: wait for that surface's first
    // frame so the move is actually seen. Same launch gate as IrisMorphSurface.
    Connections {
        target: body.Window.window
        enabled: root.warming && !root.launched
        function onFrameSwapped(): void {
            if (++root.launchFrames >= 1) root.launched = true
        }
    }
    Timer {
        interval: 90
        running: root.warming && !root.launched
        onTriggered: root.launched = true
    }
    onLaunchedChanged: if (root.launched && root.warming) root.startReveal()

    Timer {
        id: focusTimer
        interval: 160
        onTriggered: if (root.open && content.item) content.item.forceActiveFocus()
    }

    function startReveal(): void {
        root.warming = false
        reveal.stop()
        if (root.progress >= 0.999) {
            root.progress = 1
            root.settled = true
            return
        }
        reveal.from = root.progress
        reveal.to = 1
        reveal.duration = root.motion ? Math.max(0, Math.round(root.openDuration * (1 - root.progress))) : 0
        reveal.easing.type = root.openEasing
        if (root.openEasing === Easing.BezierSpline)
            reveal.easing.bezierCurve = IrisStyle.emergeCurve
        reveal.start()
        if (root.animationName === "unfold") {
            unfoldMove.stop()
            unfoldMove.from = root.unfoldAngle
            unfoldMove.to = 0
            unfoldMove.duration = Math.max(0, Math.round(root.openDuration * (1 - root.progress)))
            unfoldMove.easing.type = Easing.InOutCubic
            unfoldMove.start()
        }
    }

    function show(): void {
        const wasShown = root.shown
        if (root.progress <= 0.001) {
            root.dropSide = -1
            unfoldMove.stop()
            root.unfoldAngle = 78
        }
        root.settled = false
        root.shown = true
        focusTimer.restart()
        if (!root.motion) {
            root.warming = false
            root.launched = true
            reveal.stop()
            unfoldMove.stop()
            root.progress = 1
            root.unfoldAngle = 0
            root.settled = true
            return
        }
        // Already drawn (a reopen mid-close): no map to wait for, and no warm dip.
        if (wasShown) {
            root.startReveal()
            return
        }
        root.warming = true
        root.launched = false
        root.launchFrames = 0
    }

    function hide(): void {
        GlobalStates.centerPanelOpen = false
    }

    function close(): void {
        if (!root.shown) return
        root.warming = false
        root.launched = false
        if (root.progress >= 0.999) root.dropSide = 1
        root.settled = false
        reveal.stop()
        if (!root.motion || root.progress <= 0) {
            unfoldMove.stop()
            root.progress = 0
            root.unfoldAngle = 78
            root.shown = false
            return
        }
        reveal.from = root.progress
        reveal.to = 0
        reveal.duration = Math.round(root.closeDuration * root.progress)
        reveal.easing.type = root.closeEasing
        if (root.closeEasing === Easing.BezierSpline)
            reveal.easing.bezierCurve = IrisStyle.recedeCurve
        reveal.start()
        if (root.animationName === "unfold") {
            unfoldMove.stop()
            unfoldMove.from = root.unfoldAngle
            unfoldMove.to = 78
            unfoldMove.duration = Math.round(root.closeDuration * root.progress)
            unfoldMove.easing.type = Easing.InCubic
            unfoldMove.start()
        }
    }

    Connections {
        target: GlobalStates
        function onCenterPanelOpenChanged() {
            if (root.open) root.show()
            else root.close()
        }
    }

    Component.onCompleted: {
        if (root.open) root.show()
    }
}
