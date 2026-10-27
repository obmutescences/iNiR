pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
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
    property var pendingKill: null

    readonly property var rows: ProcessList.sorted
    readonly property real maxCpu: root.rows.reduce(
        (max, process) => Math.max(max, Number(process.cpu) || 0), 1)
    readonly property real rowHeight: Math.round(26 * IrisStyle.density)
    readonly property real cpuWidth: Math.round(150 * IrisStyle.density)
    readonly property real memWidth: Math.round(90 * IrisStyle.density)

    function memoryText(gb): string {
        const value = Number(gb)
        if (value >= 1) return value.toFixed(2) + " GB"
        return Math.round(value * 1024) + " MB"
    }
    function askKill(process): void {
        if (!process || !process.pid) return
        root.pendingKill = process
    }
    function confirmKill(): void {
        if (!root.pendingKill) return
        ProcessList.killProcess(root.pendingKill.pid)
        root.pendingKill = null
    }

    onActiveChanged: ProcessList.active = root.active
    Component.onCompleted: ProcessList.active = root.active
    Component.onDestruction: ProcessList.active = false

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.round(40 * IrisStyle.density)

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(6 * IrisStyle.density)

            Rectangle {
                width: cpuLabel.implicitWidth + Math.round(22 * IrisStyle.density)
                height: Math.round(30 * IrisStyle.density)
                radius: height / 2
                color: ProcessList.sortBy === "cpu" ? IrisStyle.accent : IrisStyle.fill
                Text {
                    id: cpuLabel
                    anchors.centerIn: parent
                    text: Translation.tr("CPU")
                    color: ProcessList.sortBy === "cpu" ? IrisStyle.inkOnAccent : IrisStyle.subtext
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ProcessList.sortBy = "cpu"
                }
            }
            Rectangle {
                width: memLabel.implicitWidth + Math.round(22 * IrisStyle.density)
                height: Math.round(30 * IrisStyle.density)
                radius: height / 2
                color: ProcessList.sortBy === "memory" ? IrisStyle.accent : IrisStyle.fill
                Text {
                    id: memLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Memory")
                    color: ProcessList.sortBy === "memory" ? IrisStyle.inkOnAccent : IrisStyle.subtext
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ProcessList.sortBy = "memory"
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: ProcessList.total >= 0
                ? Translation.tr("%1 processes").arg(ProcessList.total) : ""
            color: IrisStyle.subtext
            font.family: IrisStyle.fontNumbers
            font.pixelSize: IrisStyle.typeFootnote
        }
    }

    Item {
        id: columns
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Math.round(8 * IrisStyle.density)
        height: Math.round(22 * IrisStyle.density)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Process")
            color: IrisStyle.muted
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeCaption
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.cpuWidth + root.memWidth + Math.round(34 * IrisStyle.density)
            anchors.verticalCenter: parent.verticalCenter
            text: "PID"
            color: IrisStyle.muted
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeCaption
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.cpuWidth + root.memWidth
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("CPU")
            color: IrisStyle.muted
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeCaption
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.memWidth
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Memory")
            color: IrisStyle.muted
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeCaption
        }
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: columns.bottom
        anchors.bottom: parent.bottom
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
            id: row
            required property var modelData
            required property int index

            width: list.width - Math.round(8 * IrisStyle.density)
            height: root.rowHeight
            readonly property color dotColor: {
                const set = [IrisStyle.accent, IrisStyle.secondaryAccent, IrisStyle.success, IrisStyle.warning]
                return set[row.index % set.length]
            }

            Rectangle {
                anchors.fill: parent
                radius: IrisStyle.radiusSmall
                color: rowMouse.hovered ? IrisStyle.fill : "transparent"
            }

            Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.leftMargin: Math.round(10 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(6 * IrisStyle.density)
                height: width
                radius: width / 2
                color: row.dotColor
            }
            Text {
                anchors.left: dot.right
                anchors.leftMargin: Math.round(10 * IrisStyle.density)
                anchors.right: pidText.left
                anchors.rightMargin: Math.round(8 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                color: IrisStyle.text
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
                elide: Text.ElideRight
            }
            Text {
                id: pidText
                anchors.right: cpuBar.left
                anchors.rightMargin: Math.round(16 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.pid
                color: IrisStyle.muted
                font.family: IrisStyle.fontNumbers
                font.pixelSize: IrisStyle.typeFootnote
            }

            Item {
                id: cpuBar
                anchors.right: memText.left
                anchors.rightMargin: Math.round(18 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: root.cpuWidth
                height: Math.round(14 * IrisStyle.density)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Math.round(44 * IrisStyle.density)
                    height: Math.round(4 * IrisStyle.density)
                    radius: height / 2
                    color: IrisStyle.fillHover
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: (parent.width - Math.round(44 * IrisStyle.density))
                        * Math.max(0, Math.min(1, Number(row.modelData.cpu) / root.maxCpu))
                    height: Math.round(4 * IrisStyle.density)
                    radius: height / 2
                    color: IrisStyle.accent
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Number(row.modelData.cpu).toFixed(1)
                    color: IrisStyle.text
                    font.family: IrisStyle.fontNumbers
                    font.pixelSize: IrisStyle.typeCaption
                }
            }

            Text {
                id: memText
                anchors.right: killButton.left
                anchors.rightMargin: Math.round(12 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: root.memWidth
                horizontalAlignment: Text.AlignRight
                text: root.memoryText(row.modelData.memory)
                color: IrisStyle.subtext
                font.family: IrisStyle.fontNumbers
                font.pixelSize: IrisStyle.typeCaption
            }

            Rectangle {
                id: killButton
                anchors.right: parent.right
                anchors.rightMargin: Math.round(6 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(22 * IrisStyle.density)
                height: width
                radius: width / 2
                color: killMouse.hovered ? IrisStyle.dangerFill : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Math.round(13 * IrisStyle.density)
                    color: killMouse.hovered ? IrisStyle.inkOnDangerFill : IrisStyle.muted
                }
                HoverHandler { id: killMouse }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.askKill(row.modelData)
                }
            }

            HoverHandler { id: rowMouse }
        }
    }

    // The confirmation covers the list: ending the wrong process costs the session.
    Rectangle {
        anchors.fill: parent
        visible: root.pendingKill !== null
        color: Qt.rgba(0, 0, 0, 0.35)
        radius: IrisStyle.radiusCard

        MouseArea {
            anchors.fill: parent
            onClicked: root.pendingKill = null
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(380 * IrisStyle.density)
            height: Math.round(170 * IrisStyle.density)
            radius: IrisStyle.radiusCard
            color: IrisStyle.surfaceHighest
            border.width: 1
            border.color: IrisStyle.hairline

            Column {
                anchors.centerIn: parent
                width: parent.width - Math.round(40 * IrisStyle.density)
                spacing: Math.round(10 * IrisStyle.density)

                Text {
                    width: parent.width
                    text: Translation.tr("End process?")
                    color: IrisStyle.text
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeTitle
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.pendingKill
                        ? root.pendingKill.name + " · PID " + root.pendingKill.pid
                        : ""
                    color: IrisStyle.subtext
                    font.family: IrisStyle.fontNumbers
                    font.pixelSize: IrisStyle.typeLabel
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: Translation.tr("The process is stopped immediately. Unsaved work is lost.")
                    color: IrisStyle.muted
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                    wrapMode: Text.WordWrap
                }
                Item {
                    width: parent.width
                    height: Math.round(34 * IrisStyle.density)

                Row {
                    anchors.right: parent.right
                    spacing: Math.round(8 * IrisStyle.density)

                    Rectangle {
                        width: cancelLabel.implicitWidth + Math.round(28 * IrisStyle.density)
                        height: Math.round(34 * IrisStyle.density)
                        radius: IrisStyle.radiusSmall
                        color: cancelMouse.hovered ? IrisStyle.fillHover : IrisStyle.fill
                        Text {
                            id: cancelLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Cancel")
                            color: IrisStyle.text
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeFootnote
                        }
                        HoverHandler { id: cancelMouse }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pendingKill = null
                        }
                    }
                    Rectangle {
                        width: endLabel.implicitWidth + Math.round(28 * IrisStyle.density)
                        height: Math.round(34 * IrisStyle.density)
                        radius: IrisStyle.radiusSmall
                        color: endMouse.hovered ? IrisStyle.danger : IrisStyle.dangerFill
                        Text {
                            id: endLabel
                            anchors.centerIn: parent
                            text: Translation.tr("End process")
                            color: IrisStyle.inkOnDangerFill
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeFootnote
                        }
                        HoverHandler { id: endMouse }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmKill()
                        }
                    }
                }
                }
            }
        }
    }
}
