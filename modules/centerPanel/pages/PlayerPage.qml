pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
    readonly property var player: MprisController.activePlayer
    readonly property bool playing: root.player?.isPlaying ?? false
    readonly property real position: root.player ? MprisController.positionOf(root.player) : 0
    readonly property real length: root.player ? MprisController.lengthOf(root.player) : 0
    readonly property bool hasTrack: root.player !== null && MprisController.titleOf(root.player).length > 0
    readonly property color accent: IrisStyle.accent
    readonly property color highlight: IrisStyle.secondaryAccent
    readonly property real controlHeight: Math.round(58 * IrisStyle.density)

    function formatTime(seconds): string {
        const whole = Math.max(0, Math.floor(Number(seconds) || 0))
        const minutes = Math.floor(whole / 60)
        const rest = whole % 60
        return minutes + ":" + (rest < 10 ? "0" + rest : String(rest))
    }

    CavaProcess {
        id: cava
        active: root.active && root.playing
        sampleCount: 44
    }

    component RoundControl: Item {
        id: control
        property string icon: "play_arrow"
        property bool on: false
        property bool main: false
        property real diameter: control.main
            ? Math.round(56 * IrisStyle.density) : Math.round(38 * IrisStyle.density)
        property int iconSize: control.main
            ? Math.round(27 * IrisStyle.density) : Math.round(19 * IrisStyle.density)
        readonly property bool hovered: hover.hovered
        signal activated()

        width: control.diameter
        height: root.controlHeight

        Rectangle {
            anchors.centerIn: parent
            width: control.diameter
            height: width
            radius: width / 2
            color: control.main
                ? (control.hovered ? IrisStyle.accentHover : IrisStyle.accent)
                : (control.hovered || control.on ? IrisStyle.fillHover : "transparent")
            border.width: control.main ? 0 : 1
            border.color: IrisStyle.hairline
            antialiasing: true
            Behavior on color { ColorAnimation { duration: IrisStyle.duration(120) } }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: control.icon
            iconSize: control.iconSize
            color: control.main ? IrisStyle.inkOnAccent : (control.on ? IrisStyle.accent : IrisStyle.text)
        }
        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: control.activated()
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Math.round(10 * IrisStyle.density)
        visible: !root.hasTrack

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "music_note"
            iconSize: Math.round(56 * IrisStyle.density)
            color: IrisStyle.subtext
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Nothing playing")
            color: IrisStyle.text
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeTitle
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Start a player and the track appears here")
            color: IrisStyle.subtext
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeFootnote
        }
    }

    Row {
        id: body
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(-6 * IrisStyle.density)
        spacing: Math.round(42 * IrisStyle.density)
        visible: root.hasTrack

        Item {
            id: coverStage
            width: Math.round(300 * IrisStyle.density)
            height: width

            Rectangle {
                anchors.fill: parent
                anchors.margins: Math.round(-14 * IrisStyle.density)
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: IrisStyle.hairline
            }

            IrisArtwork {
                id: cover
                anchors.fill: parent
                circular: true
                source: root.player ? MprisController.artUrlOf(root.player) : ""
                decodeSize: Math.round(width * 1.2)

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 18000
                    loops: Animation.Infinite
                    running: root.playing
                }
            }
        }

        Column {
            id: details
            width: Math.round(500 * IrisStyle.density)
            anchors.verticalCenter: coverStage.verticalCenter
            spacing: Math.round(6 * IrisStyle.density)

            Text {
                text: Translation.tr("Now playing")
                color: root.accent
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
            Text {
                width: details.width
                text: root.player ? MprisController.titleOf(root.player) : ""
                color: root.accent
                font.family: IrisStyle.fontTitle
                font.pixelSize: Math.round(34 * IrisStyle.density)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: details.width
                text: root.player ? MprisController.artistOf(root.player) : ""
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeLabel
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: details.width
                text: root.player?.trackAlbum ?? ""
                color: IrisStyle.muted
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text.length > 0
            }

            Item { width: 1; height: Math.round(8 * IrisStyle.density) }

            Item {
                width: details.width
                height: Math.round(84 * IrisStyle.density)

                CavaSpectrum {
                    anchors.fill: parent
                    points: cava.points
                    active: root.active && root.playing && cava.audioSignalActive
                    normalizationCeiling: cava.normalizationCeiling
                    visualizerType: "bars"
                    spectrumColor: root.accent
                    spectrumColors: [root.accent, root.highlight]
                    spectrumOpacity: 0.95
                    barSpacing: Math.round(3 * IrisStyle.density)
                    barRadius: 2
                    barMinHeight: 2
                    pixelsPerBar: Math.max(4, width / 44)
                }
            }

            Item { width: 1; height: Math.round(6 * IrisStyle.density) }

            Item {
                id: progress
                width: details.width
                height: Math.round(18 * IrisStyle.density)
                readonly property real ratio: root.length > 0 ? Math.max(0, Math.min(1, root.position / root.length)) : 0

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Math.max(3, Math.round(4 * IrisStyle.density))
                    radius: height / 2
                    color: IrisStyle.fillHover
                }
                Rectangle {
                    anchors.verticalCenter: track.verticalCenter
                    width: track.width * progress.ratio
                    height: track.height
                    radius: track.radius
                    color: root.highlight
                }
                Rectangle {
                    x: track.width * progress.ratio - width / 2
                    anchors.verticalCenter: track.verticalCenter
                    width: Math.round(10 * IrisStyle.density)
                    height: width
                    radius: width / 2
                    color: root.highlight
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.length > 0
                    onClicked: mouse => MprisController.seek(root.player, mouse.x / width * root.length)
                }
            }

            Item {
                width: details.width
                height: Math.round(16 * IrisStyle.density)

                Text {
                    text: root.formatTime(root.position)
                    color: IrisStyle.subtext
                    font.family: IrisStyle.fontNumbers
                    font.pixelSize: IrisStyle.typeFootnote
                }
                Text {
                    anchors.right: parent.right
                    text: root.formatTime(root.length)
                    color: IrisStyle.subtext
                    font.family: IrisStyle.fontNumbers
                    font.pixelSize: IrisStyle.typeFootnote
                }
            }

            Item { width: 1; height: Math.round(8 * IrisStyle.density) }

            Row {
                height: root.controlHeight
                spacing: Math.round(14 * IrisStyle.density)

                RoundControl {
                    icon: "shuffle"
                    on: root.player?.shuffle ?? false
                    visible: root.player?.shuffleSupported ?? false
                    onActivated: if (root.player) root.player.shuffle = !root.player.shuffle
                }
                RoundControl {
                    icon: "skip_previous"
                    onActivated: if (root.player) root.player.previous()
                }
                RoundControl {
                    icon: root.playing ? "pause" : "play_arrow"
                    main: true
                    onActivated: if (root.player) root.player.togglePlaying()
                }
                RoundControl {
                    icon: "skip_next"
                    onActivated: if (root.player) root.player.next()
                }
            }
        }
    }
}
