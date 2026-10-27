pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.iris.style
import qs.modules.iris.components
import "pages"

Item {
    id: root

    property int tab: GlobalStates.centerPanelTab
    focus: GlobalStates.centerPanelOpen

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Tab) {
            GlobalStates.centerPanelTab = (root.tab + 1) % root.tabs.length
            event.accepted = true
        } else if (event.key === Qt.Key_Backtab) {
            GlobalStates.centerPanelTab = (root.tab + root.tabs.length - 1) % root.tabs.length
            event.accepted = true
        }
    }

    Connections {
        target: GlobalStates
        function onCenterPanelOpenChanged() {
            if (GlobalStates.centerPanelOpen)
                Qt.callLater(() => root.forceActiveFocus())
        }
    }
    property int nowTick: 0

    readonly property date now: {
        void root.nowTick
        return new Date()
    }
    readonly property var tabs: [
        { label: Translation.tr("Overview"), key: "overview", source: "pages/OverviewPage.qml" },
        { label: Translation.tr("Tray"), key: "tray", source: "pages/TrayPage.qml" },
        { label: Translation.tr("Now Playing"), key: "player", source: "pages/PlayerPage.qml" },
        { label: Translation.tr("Audio"), key: "audio", source: "pages/AudioPage.qml" },
        { label: Translation.tr("Processes"), key: "processes", source: "pages/ProcessesPage.qml" },
        { label: Translation.tr("Calendar"), key: "calendar", source: "pages/CalendarPage.qml" }
    ]
    readonly property color tabInk: IrisStyle.text
    readonly property color tabMuted: IrisStyle.subtext
    readonly property real headerHeight: Math.round(62 * IrisStyle.density)

    function pad2(value: int): string {
        return value < 10 ? "0" + value : String(value)
    }
    function closePanel(): void {
        GlobalStates.centerPanelOpen = false
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowTick += 1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Row {
                    spacing: Math.round(3 * IrisStyle.density)
                    Text {
                        text: root.pad2(root.now.getHours()) + ":" + root.pad2(root.now.getMinutes())
                        color: IrisStyle.accent
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: Math.round(30 * IrisStyle.density)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.round(5 * IrisStyle.density)
                        text: root.pad2(root.now.getSeconds())
                        color: IrisStyle.accent
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: IrisStyle.typeMeta
                    }
                }
                Text {
                    text: Qt.formatDate(root.now, "yyyy年M月d日") + " " + Lunar.weekdayName(root.now)
                        + (Lunar.lunarName(root.now).length > 0 ? " · " + Lunar.lunarName(root.now) : "")
                    color: IrisStyle.secondaryAccent
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeLabel
                }
            }

            Rectangle {
                id: indicator
                x: tabRow.x + (tabRow.itemAt(root.tab)?.x ?? 0)
                y: tabRow.y
                width: tabRow.itemAt(root.tab)?.width ?? 0
                height: tabRow.height
                radius: height / 2
                color: IrisStyle.accentContainer
                Behavior on x {
                    NumberAnimation { duration: IrisStyle.duration(180); easing.type: Easing.OutCubic }
                }
                Behavior on width {
                    NumberAnimation { duration: IrisStyle.duration(180); easing.type: Easing.OutCubic }
                }
            }

            Row {
                id: tabRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(2 * IrisStyle.density)

                Repeater {
                    model: root.tabs

                    Item {
                        id: tabItem
                        required property var modelData
                        required property int index
                        width: tabLabel.implicitWidth + Math.round(26 * IrisStyle.density)
                        height: Math.round(34 * IrisStyle.density)

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: tabItem.modelData.label
                            color: root.tab === tabItem.index ? IrisStyle.accent : root.tabMuted
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeLabel
                            font.weight: root.tab === tabItem.index ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.centerPanelTab = tabItem.index
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(4 * IrisStyle.density)

                IrisIconButton {
                    materialIcon: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    selected: BluetoothStatus.enabled
                    visible: BluetoothStatus.available
                    onClicked: BluetoothStatus.toggle()
                }
                IrisIconButton {
                    materialIcon: "power_settings_new"
                    onClicked: {
                        root.closePanel()
                        GlobalStates.sessionOpen = true
                    }
                }
                IrisIconButton {
                    materialIcon: "restart_alt"
                    onClicked: {
                        root.closePanel()
                        Session.reboot()
                    }
                }
                IrisIconButton {
                    materialIcon: "logout"
                    onClicked: {
                        root.closePanel()
                        Session.poweroff()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: IrisStyle.hairline
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Math.round(16 * IrisStyle.density)

            Loader {
                id: pageLoader
                anchors.fill: parent
                source: root.tabs[root.tab].source
                onLoaded: if (item) item.active = true
                onStatusChanged: if (status === Loader.Error) console.error("[CenterPanel] page failed:", source)
            }
        }
    }

    Shortcut {
        sequence: "1"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 0
    }
    Shortcut {
        sequence: "2"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 1
    }
    Shortcut {
        sequence: "3"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 2
    }
    Shortcut {
        sequence: "4"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 3
    }
    Shortcut {
        sequence: "5"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 4
    }
    Shortcut {
        sequence: "6"
        enabled: GlobalStates.centerPanelOpen
        onActivated: GlobalStates.centerPanelTab = 5
    }

    Component.onCompleted: {
        if (GlobalStates.centerPanelOpen)
            Qt.callLater(() => root.forceActiveFocus())
        Lunar.request(root.now)
        Lunar.requestNext(root.now)
    }
}
