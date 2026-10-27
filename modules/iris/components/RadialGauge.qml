pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.iris.style

/**
 * A 270 degree gauge for one network direction. The arc, ticks and needle
 * are drawn in one Canvas paint, so a value update is one repaint.
 */
Item {
    id: root

    property real value: 0
    property color tint: IrisStyle.accent
    property string label: ""
    property string figure: ""
    property string unit: ""

    implicitWidth: Math.round(150 * IrisStyle.density)
    implicitHeight: Math.round(150 * IrisStyle.density)

    readonly property real startAngle: Math.PI * 0.75
    readonly property real sweep: Math.PI * 1.5

    Canvas {
        id: dial
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height
            ctx.clearRect(0, 0, w, h)
            const cx = w / 2
            const cy = h / 2
            if (w < 8 || h < 8) return
            const line = Math.max(3, Math.min(Math.round(7 * IrisStyle.density), Math.floor(Math.min(w, h) / 8)))
            const r = Math.max(2, Math.min(w, h) / 2 - line - 3)

            ctx.lineCap = "round"
            ctx.lineWidth = line
            ctx.strokeStyle = Qt.rgba(IrisStyle.text.r, IrisStyle.text.g, IrisStyle.text.b, 0.10)
            ctx.beginPath()
            ctx.arc(cx, cy, r, root.startAngle, root.startAngle + root.sweep)
            ctx.stroke()

            const clamped = Math.max(0, Math.min(1, root.value))
            if (clamped > 0.005) {
                ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.95)
                ctx.beginPath()
                ctx.arc(cx, cy, r, root.startAngle, root.startAngle + root.sweep * clamped)
                ctx.stroke()
            }

            const angle = root.startAngle + root.sweep * clamped
            const needleFrom = r * 0.24
            const needleTo = r * 0.78
            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.95)
            ctx.lineWidth = Math.max(2, Math.round(2.5 * IrisStyle.density))
            ctx.beginPath()
            ctx.moveTo(cx + Math.cos(angle) * needleFrom, cy + Math.sin(angle) * needleFrom)
            ctx.lineTo(cx + Math.cos(angle) * needleTo, cy + Math.sin(angle) * needleTo)
            ctx.stroke()

            ctx.fillStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.95)
            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(3, Math.round(3.5 * IrisStyle.density)), 0, Math.PI * 2)
            ctx.fill()
        }
    }

    onValueChanged: dial.requestPaint()
    onTintChanged: dial.requestPaint()
    Component.onCompleted: dial.requestPaint()

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        text: root.label
        color: IrisStyle.subtext
        font.family: IrisStyle.fontMain
        font.pixelSize: IrisStyle.typeFootnote
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(2 * IrisStyle.density)
        spacing: 0

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Text {
                text: root.figure
                color: IrisStyle.text
                font.family: IrisStyle.fontNumbers
                font.pixelSize: Math.round(22 * IrisStyle.density)
                font.weight: Font.Bold
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(3 * IrisStyle.density)
                text: root.unit
                color: IrisStyle.subtext
                font.family: IrisStyle.fontNumbers
                font.pixelSize: IrisStyle.typeCaption
            }
        }
    }
}
