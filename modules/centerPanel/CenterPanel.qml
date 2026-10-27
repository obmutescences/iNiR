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
    property bool presented: false
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
        shapes: root.shown && root.presented
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
        onActivated: GlobalStates.centerPanelTab = (GlobalStates.centerPanelTab + 1) % 5
    }
    Shortcut {
        sequence: "Shift+Tab"
        enabled: root.open
        onActivated: GlobalStates.centerPanelTab = (GlobalStates.centerPanelTab + 4) % 5
    }

    Item {
        id: body

        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        z: 1
        clip: true
        readonly property real radius: root.radius

        opacity: root.presented ? 1 : 0
        scale: root.presented ? 1 : 0.96
        transform: Translate { y: root.presented ? 0 : Math.round(18 * IrisStyle.density) }

        Behavior on opacity {
            NumberAnimation {
                duration: root.presented ? Math.round(IrisStyle.settleDuration * 0.7) : IrisStyle.revealDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.presented ? IrisStyle.settleDuration : IrisStyle.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.presented ? IrisStyle.emergeCurve : IrisStyle.recedeCurve
            }
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: body.radius

            Loader {
                anchors.fill: parent
                active: IrisStyle.glassWallpaper
                sourceComponent: IrisGlassPane {
                    sceneOffset: Qt.point(body.x, body.y)
                    windowOffset: Qt.point(0, 0)
                    live: root.presented
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
            visible: root.presented
            source: "CenterPanelContent.qml"
            onStatusChanged: if (status === Loader.Error) console.error("[CenterPanel] content failed to load")
        }
    }

    function show(): void {
        closeTimer.stop()
        root.shown = true
        Qt.callLater(() => { root.presented = true })
        focusTimer.restart()
    }

    Timer {
        id: focusTimer
        interval: 160
        onTriggered: if (root.open && content.item) content.item.forceActiveFocus()
    }

    function hide(): void {
        GlobalStates.centerPanelOpen = false
    }

    function close(): void {
        root.presented = false
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: Math.max(180, IrisStyle.settleDuration)
        onTriggered: {
            if (!root.open) {
                root.presented = false
                root.shown = false
            }
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
        if (root.open) {
            root.shown = true
            root.presented = true
        }
    }
}
