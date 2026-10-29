pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import "PickerMath.js" as M

Item {
    id: card

    required property var cardData
    // Driven by the picker: 0 idle, 1 entering, 2 exiting.
    property int phase: 0
    property real clock: 0
    property string mode: "fly"
    property string prefix: ""
    property bool focused: false
    property bool animationsEnabled: true
    property color wpPrimary: "#3d5c41"
    property color wpPrimaryHover: "#4a6d4f"
    property color wpPrimaryStrong: "#567d5c"
    property color wpAccent: "#c8e6c9"
    property color wpInk: "#e8a33d"

    signal activated(int windowId)

    width: cardData.w ?? 240
    height: cardData.h ?? 196
    x: cardData.x ?? 0
    y: cardData.y ?? 0
    z: focused ? 20 : (card.hovered ? 10 : 1)

    readonly property real thumbRatio: 10 / 16
    readonly property real titleSize: Math.max(11, Math.min(15, width * 0.047))
    readonly property real smallSize: Math.max(8.5, Math.min(10.5, width * 0.036))
    readonly property int thumbHeight: Math.round(width * thumbRatio)

    // ---- progress -----------------------------------------------------
    readonly property real p: {
        if (card.phase === 0)
            return 0
        const delay = Number(card.cardData.delay ?? 0)
        if (card.phase === 1)
            return M.entryProgress(card.mode, card.clock, delay)
        return M.exitProgress(card.clock, delay)
    }

    readonly property real fade: {
        if (card.mode === "unfold")
            return 1
        if (card.phase === 0)
            return 0
        const delay = Number(card.cardData.delay ?? 0)
        if (card.phase === 1)
            return M.entryOpacity(card.mode, card.clock, delay)
        return M.exitOpacity(card.clock, delay)
    }

    readonly property string code: String(card.cardData.code ?? "")
    readonly property bool dimmed: card.prefix.length > 0 && !card.code.startsWith(card.prefix)
    readonly property var modeParams: M.modeParams(card.mode)

    // ---- hover / focus ------------------------------------------------
    property bool hovered: false

    property real hoverLift: hovered ? -4 : 0
    Behavior on hoverLift {
        enabled: card.animationsEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    property real hoverScale: hovered ? 1.03 : 1
    Behavior on hoverScale {
        enabled: card.animationsEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    property real focusScale: card.focused ? 1.03 : 1
    Behavior on focusScale {
        enabled: card.animationsEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    // ---- transforms ---------------------------------------------------
    readonly property real startScaleX: cardData.sx ?? 1
    readonly property real startScaleY: cardData.sy ?? 1
    readonly property real scaleProgress: card.mode === "zoom_rotate"
        ? (card.modeParams?.scale ?? 0.34) + (1 - (card.modeParams?.scale ?? 0.34)) * card.p
        : 1

    readonly property real tx: card.mode === "fly" ? (cardData.tx ?? 0) * (1 - card.p) : 0
    readonly property real ty: {
        const progress = card.p
        let base = 0
        if (card.mode === "fly")
            base = (cardData.ty ?? 0) * (1 - progress)
        else if (card.mode === "slide_up" || card.mode === "flip")
            base = (card.mode === "flip" ? 26 : 56) * (1 - progress)
        return base + card.hoverLift + (card.focused ? -4 : 0)
    }
    readonly property real sx: {
        if (card.mode === "fly")
            return (1 + (card.startScaleX - 1) * (1 - card.p)) * card.hoverScale * card.focusScale
        if (card.mode === "zoom_rotate")
            return card.scaleProgress * card.hoverScale * card.focusScale
        return card.hoverScale * card.focusScale
    }
    readonly property real sy: {
        if (card.mode === "fly")
            return (1 + (card.startScaleY - 1) * (1 - card.p)) * card.hoverScale * card.focusScale
        if (card.mode === "zoom_rotate")
            return card.scaleProgress * card.hoverScale * card.focusScale
        return card.hoverScale * card.focusScale
    }
    readonly property real cardRotation: card.mode === "zoom_rotate" ? -10 * (1 - card.p) : 0
    readonly property real rotationX: card.mode === "flip" ? 82 * (1 - card.p) : 0
    readonly property real originX: card.mode === "fly" ? 0 : width / 2
    readonly property real originY: card.mode === "flip" ? height : (card.mode === "fly" ? 0 : height / 2)

    opacity: card.fade * (card.dimmed ? 0.35 : 1)

    transform: [
        Translate { x: card.tx; y: card.ty },
        Scale {
            xScale: card.sx
            yScale: card.sy
            origin.x: card.originX
            origin.y: card.originY
        },
        Rotation {
            angle: card.cardRotation
            origin.x: card.originX
            origin.y: card.originY
        },
        Rotation {
            axis: Qt.vector3d(1, 0, 0)
            angle: card.rotationX
            origin.x: card.originX
            origin.y: card.originY
        }
    ]

    // ---- visual -------------------------------------------------------
    Item {
        id: clipBox
        width: card.width
        height: card.mode === "unfold" ? Math.max(0, card.height * card.p) : card.height
        clip: card.mode === "unfold"

        Item {
            id: body
            width: card.width
            height: card.height

            // Soft colour glow, behind the card: only the halo is visible.
            Rectangle {
                id: glowSource
                anchors.fill: parent
                radius: 14
                color: card.wpAccent
            }
            MultiEffect {
                source: glowSource
                anchors.fill: glowSource
                shadowEnabled: true
                shadowColor: card.wpAccent
                shadowBlur: 0.9
                shadowOpacity: 1.0
                shadowScale: 1.03
                opacity: card.focused ? 1 : 0
                Behavior on opacity {
                    enabled: card.animationsEnabled
                    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                }
            }

            Rectangle {
                id: surface
                anchors.fill: parent
                radius: 14
                color: card.wpPrimary
                border.width: 1
                border.color: card.wpPrimaryStrong
            }

            Item {
                id: thumb
                width: parent.width
                height: card.thumbHeight
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: thumb.width
                        height: thumb.height
                        topLeftRadius: 13
                        topRightRadius: 13
                        bottomLeftRadius: 0
                        bottomRightRadius: 0
                        color: "black"
                    }
                }

                Image {
                    id: preview
                    anchors.fill: parent
                    source: WindowPreviewService.getPreviewUrl(Number(card.cardData.id ?? -1))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Rectangle {
                    anchors.fill: parent
                    visible: preview.status !== Image.Ready
                    color: Qt.rgba(0.05, 0.07, 0.1, 0.92)
                    Image {
                        anchors.centerIn: parent
                        width: Math.min(48, thumb.width * 0.3)
                        height: width
                        source: Quickshell.iconPath(String(card.cardData.appId ?? ""), "application-x-executable")
                        fillMode: Image.PreserveAspectFit
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(76, card.thumbHeight * 0.5)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.42) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                    }
                }
            }

            Item {
                id: info
                anchors.top: thumb.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 8
                anchors.bottomMargin: 10

                Text {
                    id: titleText
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: String(card.cardData.title ?? "")
                    color: card.wpInk
                    font.family: Appearance.font.family.main
                    font.pixelSize: card.titleSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    anchors.top: titleText.bottom
                    anchors.topMargin: 3
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: String(card.cardData.appId ?? "").toUpperCase()
                    color: Qt.rgba(card.wpInk.r, card.wpInk.g, card.wpInk.b, 0.85)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: card.smallSize
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

        }
    }

    // Focus ring: a state, not an animation layer.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: 15
        color: "transparent"
        border.width: 2
        border.color: card.wpAccent
        opacity: card.focused ? 1 : 0
        Behavior on opacity {
            enabled: card.animationsEnabled
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }
    }

    // Keycap rides across the card top edge: 21px outside, 11px inside.
    Item {
        id: keycap
        width: Math.max(36, keyLabel.implicitWidth + 18)
        height: 32
        anchors.horizontalCenter: parent.horizontalCenter
        y: -22
        visible: card.code.length > 0
        opacity: card.mode === "unfold" ? Math.max(0, Math.min(1, (card.p - 0.8) / 0.2)) : 1

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.32)
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.22)
            gradient: Gradient {
                GradientStop { position: 0; color: card.focused ? card.wpInk : card.wpPrimaryStrong }
                GradientStop { position: 1; color: card.focused ? Qt.darker(card.wpInk, 1.12) : card.wpPrimary }
            }

            Text {
                id: keyLabel
                anchors.centerIn: parent
                text: card.code
                color: card.focused ? card.wpPrimary : card.wpInk
                font.family: Appearance.font.family.monospace
                font.pixelSize: 15
                font.weight: Font.Bold
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: card.hovered = containsMouse
        onClicked: card.activated(Number(card.cardData.id ?? -1))
        onEntered: card.hovered = true
        onExited: card.hovered = false
    }
}
