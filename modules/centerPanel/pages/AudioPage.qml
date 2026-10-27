pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.iris.style
import qs.modules.iris.components

Item {
    id: root
    anchors.fill: parent

    property bool active: false
    readonly property real maxVolume: 1.0
    readonly property real volume: Math.max(0, Number(Audio.value) || 0)
    readonly property bool muted: Audio.sink?.audio?.muted ?? false
    readonly property var devices: Audio.outputDevices

    function deviceName(node): string {
        const friendly = Audio.friendlyDeviceName(node)
        if (friendly && friendly.length > 0) return friendly
        return node?.description ?? node?.name ?? Translation.tr("Unknown device")
    }
    function deviceDetail(node): string {
        const name = String(node?.name ?? "")
        if (/bluez|blue/i.test(name)) return "Bluetooth"
        if (/hdmi|display/i.test(name + String(node?.description ?? ""))) return "HDMI / DisplayPort"
        if (/usb|dac/i.test(name)) return "USB"
        return "Analog"
    }
    function deviceIcon(node): string {
        const text = String(node?.name ?? "") + " " + String(node?.description ?? "")
        if (/head|airpod|buds|bluez/i.test(text)) return "headphones"
        if (/hdmi|display/i.test(text)) return "tv"
        if (/usb|dac/i.test(text)) return "usb"
        return "speaker"
    }
    function isCurrent(node): bool {
        return (Audio.defaultSink?.id ?? -1) === (node?.id ?? -2)
    }
    function pct(value): string {
        return String(Math.round(Math.max(0, Math.min(root.maxVolume, Number(value) || 0)) * 100))
    }
    function setFromRatio(ratio): void {
        Audio.setSinkVolume(Math.max(0, Math.min(1, ratio)) * root.maxVolume)
    }

    Row {
        anchors.fill: parent
        spacing: Math.round(28 * IrisStyle.density)

        Item {
            id: devicesPane
            width: Math.round(parent.width * 0.58)
            height: parent.height

            Text {
                id: devicesTitle
                text: Translation.tr("Output devices")
                color: IrisStyle.text
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeHeadline
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.devices.length + " " + Translation.tr("devices")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
            }

            // 当前设备居中，其余设备像卫星一样围在周围，白线从圆心牵出去。
            Item {
                id: orbit
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: devicesTitle.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: Math.round(14 * IrisStyle.density)
                visible: root.devices.length > 0

                readonly property real d: IrisStyle.density
                readonly property var satellites: root.devices.filter(device => !root.isCurrent(device))
                readonly property var coreDevice: Audio.defaultSink ?? (root.devices.length > 0 ? root.devices[0] : null)
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                readonly property real coreSize: Math.round(Math.min(200 * d, Math.min(width, height) * 0.42))
                readonly property real orbitX: Math.round(Math.min(width * 0.36, 285 * d))
                readonly property real orbitY: Math.round(Math.min(height * 0.32, 235 * d))
                property bool revealed: false
                property real phase: 0
                readonly property real spin: Math.PI * 2 / 90

                Component.onCompleted: orbit.revealed = true

                function nodeAngle(index): real {
                    return (index / Math.max(1, orbit.satellites.length)) * Math.PI * 2 + orbit.phase
                }

                Timer {
                    interval: 33
                    repeat: true
                    running: root.active && GlobalStates.centerPanelOpen && orbit.satellites.length > 0
                    onTriggered: {
                        orbit.phase = (orbit.phase + 0.033 * orbit.spin) % (Math.PI * 2)
                        threads.requestPaint()
                    }
                }

                Canvas {
                    id: threads
                    anchors.fill: parent
                    z: 0
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < orbit.satellites.length; i++) {
                            const angle = orbit.nodeAngle(i)
                            const endX = orbit.cx + Math.cos(angle) * orbit.orbitX
                            const endY = orbit.cy + Math.sin(angle) * orbit.orbitY
                            let dx = endX - orbit.cx
                            let dy = endY - orbit.cy
                            const span = Math.max(1, Math.hypot(dx, dy))
                            dx /= span
                            dy /= span
                            const startX = orbit.cx + dx * (orbit.coreSize / 2 - 2)
                            const startY = orbit.cy + dy * (orbit.coreSize / 2 - 2)
                            const bend = (i % 2 === 0 ? 1 : -1) * Math.min(24, span * 0.12)
                            const controlX = (startX + endX) / 2 - dy * bend
                            const controlY = (startY + endY) / 2 + dx * bend

                            const accent = IrisStyle.accent
                            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.10)
                            ctx.lineWidth = 6
                            ctx.beginPath()
                            ctx.moveTo(startX, startY)
                            ctx.quadraticCurveTo(controlX, controlY, endX, endY)
                            ctx.stroke()

                            const gradient = ctx.createLinearGradient(startX, startY, endX, endY)
                            gradient.addColorStop(0, Qt.rgba(accent.r, accent.g, accent.b, 0.65))
                            gradient.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0.22))
                            ctx.strokeStyle = gradient
                            ctx.lineWidth = 1.3
                            ctx.beginPath()
                            ctx.moveTo(startX, startY)
                            ctx.quadraticCurveTo(controlX, controlY, endX, endY)
                            ctx.stroke()
                        }
                    }

                    Connections {
                        target: orbit
                        function onSatellitesChanged(): void { threads.requestPaint() }
                    }
                }



                Item {
                    id: coreNode
                    width: orbit.coreSize
                    height: width
                    x: Math.round(orbit.cx - width / 2)
                    y: Math.round(orbit.cy - height / 2)
                    z: 1
                    opacity: orbit.revealed ? 1 : 0
                    scale: (orbit.revealed ? 1 : 0.88) * coreNode.popScale
                    property real popScale: 1

                    Behavior on opacity { NumberAnimation { duration: IrisStyle.duration(280) } }
                    Behavior on scale { NumberAnimation { duration: IrisStyle.duration(460); easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                    Connections {
                        target: Audio
                        function onDefaultSinkChanged(): void { corePop.restart() }
                    }

                    SequentialAnimation {
                        id: corePop
                        NumberAnimation { target: coreNode; property: "popScale"; to: 0.94; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: coreNode; property: "popScale"; to: 1; duration: 300; easing.type: Easing.OutBack }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: parent.width + Math.round(96 * orbit.d)
                        height: width

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: root.active && GlobalStates.centerPanelOpen
                            NumberAnimation { to: 0.6; duration: 2400; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 2400; easing.type: Easing.InOutSine }
                        }

                        Canvas {
                            anchors.fill: parent
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const center = width / 2
                                const accent = IrisStyle.secondaryAccent
                                const glow = ctx.createRadialGradient(center, center, center * 0.34, center, center, center)
                                glow.addColorStop(0, Qt.rgba(accent.r, accent.g, accent.b, 0.18))
                                glow.addColorStop(0.6, Qt.rgba(accent.r, accent.g, accent.b, 0.08))
                                glow.addColorStop(1, Qt.rgba(accent.r, accent.g, accent.b, 0.0))
                                ctx.fillStyle = glow
                                ctx.fillRect(0, 0, width, height)
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        border.width: 1
                        border.color: Qt.rgba(IrisStyle.secondaryAccent.r, IrisStyle.secondaryAccent.g, IrisStyle.secondaryAccent.b, 0.70)
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
                            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.02) }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.16) }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - Math.round(44 * orbit.d)
                        spacing: Math.round(5 * orbit.d)

                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.deviceIcon(orbit.coreDevice)
                            iconSize: Math.round(44 * orbit.d)
                            color: IrisStyle.secondaryAccent
                        }
                        Text {
                            width: parent.width
                            text: root.deviceName(orbit.coreDevice)
                            color: IrisStyle.text
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeBody
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: orbit.coreDevice ? Translation.tr("Connected") : Translation.tr("No output device")
                            color: IrisStyle.secondaryAccent
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeFootnote
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Repeater {
                    model: orbit.satellites

                    Rectangle {
                        id: satellite
                        required property var modelData
                        required property int index
                        readonly property real angle: orbit.nodeAngle(satellite.index)
                        property bool entered: false

                        width: Math.round(satelliteRow.implicitWidth + 34 * orbit.d)
                        height: Math.round(52 * orbit.d)
                        x: Math.round(orbit.cx + Math.cos(satellite.angle) * orbit.orbitX - satellite.width / 2)
                        y: Math.round(orbit.cy + Math.sin(satellite.angle) * orbit.orbitY - satellite.height / 2)
                        z: 2
                        radius: height / 2
                        antialiasing: true
                        color: satelliteHover.hovered ? IrisStyle.fillHover : IrisStyle.fill
                        border.width: 1
                        border.color: Qt.rgba(IrisStyle.accent.r, IrisStyle.accent.g, IrisStyle.accent.b,
                            satelliteHover.hovered ? 0.70 : 0.35)
                        opacity: satellite.entered ? 1 : 0
                        scale: (satellite.entered ? 1 : 0.9) * (satelliteHover.hovered ? 1.04 : 1)

                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        Behavior on opacity { NumberAnimation { duration: IrisStyle.duration(260) } }
                        Behavior on scale { NumberAnimation { duration: IrisStyle.duration(380); easing.type: Easing.OutBack } }

                        Timer {
                            interval: 90 + satellite.index * 70
                            running: root.active && !satellite.entered
                            onTriggered: satellite.entered = true
                        }

                        Row {
                            id: satelliteRow
                            anchors.centerIn: parent
                            spacing: Math.round(9 * orbit.d)

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.deviceIcon(satellite.modelData)
                                iconSize: Math.round(18 * orbit.d)
                                color: IrisStyle.accent
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    width: Math.min(implicitWidth, Math.round(150 * orbit.d))
                                    text: root.deviceName(satellite.modelData)
                                    color: IrisStyle.text
                                    font.family: IrisStyle.fontMain
                                    font.pixelSize: IrisStyle.typeLabel
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: Math.min(implicitWidth, Math.round(150 * orbit.d))
                                    text: root.deviceDetail(satellite.modelData)
                                    color: IrisStyle.subtext
                                    font.family: IrisStyle.fontMain
                                    font.pixelSize: IrisStyle.typeFootnote
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        HoverHandler { id: satelliteHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Audio.setDefaultSink(satellite.modelData)
                        }
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                visible: root.devices.length === 0
                text: Translation.tr("No output devices")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeBody
            }
        }

        Item {
            id: volumePane
            width: parent.width - devicesPane.width - Math.round(28 * IrisStyle.density)
            height: parent.height

            LiquidCard {
                anchors.fill: parent
                title: Translation.tr("Volume")
                figure: root.pct(root.volume)
                unit: "%"
                detail: root.devices.length > 0 && Audio.defaultSink
                    ? root.deviceName(Audio.defaultSink) : Translation.tr("No output device")
                value: Math.max(0, Math.min(1, root.volume / root.maxVolume))
                tint: IrisStyle.accent
                animating: root.active
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => root.setFromRatio(1 - mouse.y / height)
                onPositionChanged: mouse => { if (pressed) root.setFromRatio(1 - mouse.y / height) }
            }

            Rectangle {
                id: muteButton
                z: 2
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Math.round(14 * IrisStyle.density)
                anchors.rightMargin: Math.round(16 * IrisStyle.density)
                width: Math.round(34 * IrisStyle.density)
                height: width
                radius: width / 2
                color: muteHover.hovered ? IrisStyle.fillHover : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.muted ? "volume_off" : "volume_up"
                    iconSize: Math.round(20 * IrisStyle.density)
                    color: root.muted ? IrisStyle.danger : IrisStyle.text
                }
                HoverHandler { id: muteHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.toggleMute()
                }
            }
        }
    }
}
