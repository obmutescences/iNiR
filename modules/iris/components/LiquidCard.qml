pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.iris.style

/**
 * A usage card whose lower part is a tinted liquid. The surface height follows
 * the value, two waves travel in opposite directions at a low frame rate, and
 * everything stops when the card is off screen.
 */
Rectangle {
    id: root

    property string title: ""
    property real value: 0
    property string figure: ""
    property string unit: "%"
    property string detail: ""
    property string badge: ""
    property color tint: IrisStyle.accent
    property bool animating: false
    property real phase: 0

    radius: IrisStyle.radiusCard
    color: IrisStyle.fill
    border.width: 1
    border.color: IrisStyle.hairline
    antialiasing: true
    clip: true

    readonly property real level: root.height * (1 - Math.max(0.03, Math.min(1, root.value)))
    readonly property real amplitude: Math.max(3, Math.round(7 * IrisStyle.density))

    Canvas {
        id: water
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width < 2 || height < 2) return
            root.paintWave(ctx, root.phase, 0.5, 0.62, 1.0)
            root.paintWave(ctx, -root.phase * 0.7, 0.28, 0.42, 0.7)
        }
    }

    function paintWave(ctx, phase, alphaTop, alphaBottom, frequency): void {
        const level = root.level
        const amp = root.amplitude
        ctx.beginPath()
        ctx.moveTo(0, level)
        for (let x = 0; x <= root.width; x += 4) {
            const y = level + Math.sin((x / Math.max(1, root.width)) * Math.PI * 2 * frequency + phase) * amp
            ctx.lineTo(x, y)
        }
        ctx.lineTo(root.width, root.height)
        ctx.lineTo(0, root.height)
        ctx.closePath()
        const gradient = ctx.createLinearGradient(0, level, 0, root.height)
        gradient.addColorStop(0, Qt.rgba(root.tint.r, root.tint.g, root.tint.b, alphaTop))
        gradient.addColorStop(1, Qt.rgba(root.tint.r, root.tint.g, root.tint.b, alphaBottom))
        ctx.fillStyle = gradient
        ctx.fill()
    }

    Timer {
        interval: 42
        running: root.animating
        repeat: true
        onTriggered: {
            root.phase += 0.11
            water.requestPaint()
        }
    }
    onLevelChanged: water.requestPaint()
    onWidthChanged: water.requestPaint()
    onHeightChanged: water.requestPaint()

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: Math.round(18 * IrisStyle.density)
        anchors.topMargin: Math.round(16 * IrisStyle.density)
        text: root.title
        color: IrisStyle.subtext
        font.family: IrisStyle.fontMain
        font.pixelSize: IrisStyle.typeMeta
        font.weight: IrisStyle.weight(Font.DemiBold)
        font.letterSpacing: 0.4
    }

    Rectangle {
        visible: root.badge.length > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Math.round(16 * IrisStyle.density)
        anchors.topMargin: Math.round(14 * IrisStyle.density)
        implicitWidth: badgeText.implicitWidth + Math.round(16 * IrisStyle.density)
        implicitHeight: badgeText.implicitHeight + Math.round(6 * IrisStyle.density)
        radius: height / 2
        color: IrisStyle.fillHover

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            color: IrisStyle.subtext
            font.family: IrisStyle.fontNumbers
            font.pixelSize: IrisStyle.typeFootnote
        }
    }

    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.round(18 * IrisStyle.density)
        anchors.bottomMargin: Math.round(16 * IrisStyle.density)
        spacing: 2

        Row {
            spacing: 2
            Text {
                text: root.figure
                color: IrisStyle.text
                font.family: IrisStyle.fontNumbers
                font.pixelSize: Math.round(38 * IrisStyle.density)
                font.weight: Font.Bold
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(6 * IrisStyle.density)
                text: root.unit
                color: IrisStyle.subtext
                font.family: IrisStyle.fontNumbers
                font.pixelSize: IrisStyle.typeMeta
            }
        }
        Text {
            text: root.detail
            visible: text.length > 0
            color: IrisStyle.subtext
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeFootnote
            elide: Text.ElideRight
            width: root.width - Math.round(36 * IrisStyle.density)
        }
    }
}
