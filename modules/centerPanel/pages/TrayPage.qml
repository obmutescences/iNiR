pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common.widgets
import qs.modules.iris.style

/**
 * 运行中的应用：左侧列出托盘项，右侧显示当前应用的菜单。
 * 鼠标移到应用上即时切换；带子菜单的条目悬停时原地展开，
 * 这样菜单仍在面板内，不会弹出独立窗口。
 */
Item {
    id: root
    anchors.fill: parent

    property bool active: false
    property int currentIndex: 0
    // 当前菜单里展开的顶层条目，-1 表示全部收起。
    property int expandedIndex: -1

    readonly property var items: SystemTray.items.values
    readonly property int safeIndex: root.items.length > 0
        ? Math.min(root.currentIndex, root.items.length - 1) : -1
    readonly property var currentItem: root.safeIndex >= 0 ? root.items[root.safeIndex] : null

    readonly property real gap: Math.round(18 * IrisStyle.density)
    readonly property real railWidth: Math.round(300 * IrisStyle.density)
    readonly property real pad: Math.round(26 * IrisStyle.density)

    QsMenuOpener {
        id: menuOpener
        menu: root.currentItem ? root.currentItem.menu : null
    }

    readonly property var entries: (root.currentItem?.hasMenu ?? false) && menuOpener.children
        ? menuOpener.children.values : []

    function displayName(item): string {
        if (!item) return ""
        const tooltip = String(item.tooltipTitle ?? "").trim()
        if (tooltip.length > 0) return tooltip
        const title = String(item.title ?? "").trim()
        if (title.length > 0) return title
        return String(item.id ?? "")
    }
    function subtitleOf(item): string {
        if (!item) return ""
        const description = String(item.tooltipDescription ?? "").trim()
        return description.length > 0 ? description : String(item.id ?? "")
    }
    function hoverEntry(index, entry): void {
        if (!(entry?.hasChildren ?? false)) {
            root.expandedIndex = -1
            return
        }
        root.expandedIndex = index
    }
    function activateEntry(index, entry): void {
        if (!(entry?.enabled ?? false)) return
        if (entry?.hasChildren ?? false) {
            root.expandedIndex = root.expandedIndex === index ? -1 : index
            return
        }
        entry.triggered()
        root.expandedIndex = -1
    }

    onCurrentIndexChanged: root.expandedIndex = -1
    onEntriesChanged: root.expandedIndex = -1

    ListView {
        id: rail
        width: root.railWidth
        height: parent.height
        visible: root.items.length > 0
        clip: true
        spacing: Math.round(4 * IrisStyle.density)
        model: root.items
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: appRow
            required property var modelData
            required property int index
            readonly property bool selected: root.safeIndex === appRow.index

            width: rail.width - Math.round(8 * IrisStyle.density)
            height: Math.round(62 * IrisStyle.density)
            radius: IrisStyle.radiusSmall
            color: appRow.selected ? IrisStyle.fillHover
                : (appHover.hovered ? IrisStyle.fill : "transparent")
            border.width: appRow.selected ? 1 : 0
            border.color: IrisStyle.hairline

            Rectangle {
                visible: appRow.selected
                anchors.left: parent.left
                anchors.leftMargin: Math.round(8 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(3 * IrisStyle.density)
                height: Math.round(22 * IrisStyle.density)
                radius: width / 2
                color: IrisStyle.accent
            }

            Image {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Math.round(18 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(28 * IrisStyle.density)
                height: width
                source: appRow.modelData?.icon ?? ""
                sourceSize: Qt.size(56, 56)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
            }

            Column {
                id: appLabels
                anchors.left: appIcon.right
                anchors.leftMargin: Math.round(12 * IrisStyle.density)
                anchors.right: parent.right
                anchors.rightMargin: Math.round(12 * IrisStyle.density)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(2 * IrisStyle.density)

                Text {
                    width: parent.width
                    text: root.displayName(appRow.modelData)
                    color: IrisStyle.text
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeLabel
                    font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.subtitleOf(appRow.modelData)
                    color: IrisStyle.muted
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                    elide: Text.ElideRight
                }
            }

            HoverHandler {
                id: appHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (appHover.hovered) root.currentIndex = appRow.index
            }
        }
    }

    Rectangle {
        id: detail
        anchors.left: rail.right
        anchors.leftMargin: root.gap
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: root.items.length > 0
        radius: IrisStyle.radiusCard
        color: IrisStyle.fill
        border.width: 1
        border.color: IrisStyle.hairline

        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: root.pad

            Row {
                id: head
                width: parent.width
                height: Math.round(58 * IrisStyle.density)
                spacing: Math.round(16 * IrisStyle.density)

                Rectangle {
                    width: Math.round(58 * IrisStyle.density)
                    height: width
                    radius: Math.round(15 * IrisStyle.density)
                    color: IrisStyle.fill
                    border.width: 1
                    border.color: IrisStyle.hairline

                    Image {
                        anchors.centerIn: parent
                        width: Math.round(32 * IrisStyle.density)
                        height: width
                        source: root.currentItem?.icon ?? ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: head.width - Math.round(58 * IrisStyle.density) - head.spacing
                    spacing: Math.round(3 * IrisStyle.density)

                    Text {
                        width: parent.width
                        text: root.displayName(root.currentItem)
                        color: IrisStyle.text
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeTitleLarge
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.subtitleOf(root.currentItem)
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeFootnote
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                id: divider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: head.bottom
                anchors.topMargin: Math.round(16 * IrisStyle.density)
                height: 1
                color: IrisStyle.hairline
            }

            ListView {
                id: menuList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: divider.bottom
                anchors.topMargin: Math.round(8 * IrisStyle.density)
                anchors.bottom: parent.bottom
                visible: root.entries.length > 0
                clip: true
                spacing: Math.round(2 * IrisStyle.density)
                model: root.entries
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Column {
                    id: topEntry
                    required property var modelData
                    required property int index
                    readonly property bool expanded: root.expandedIndex === topEntry.index

                    width: menuList.width - Math.round(8 * IrisStyle.density)
                    height: implicitHeight

                    MenuRow {
                        width: topEntry.width
                        entryData: topEntry.modelData
                        expanded: topEntry.expanded
                        onHovered: root.hoverEntry(topEntry.index, topEntry.modelData)
                        onActivated: root.activateEntry(topEntry.index, topEntry.modelData)
                    }

                    QsMenuOpener {
                        id: childOpener
                        menu: topEntry.expanded && (topEntry.modelData?.hasChildren ?? false)
                            ? topEntry.modelData : null
                    }

                    Repeater {
                        model: topEntry.expanded && (topEntry.modelData?.hasChildren ?? false)
                            ? (childOpener.children ? childOpener.children.values : []) : []

                        delegate: MenuRow {
                            required property var modelData
                            width: topEntry.width
                            indent: Math.round(18 * IrisStyle.density)
                            nested: true
                            entryData: modelData
                            onActivated: {
                                if (!(modelData?.enabled ?? false)) return
                                if (modelData?.hasChildren ?? false) return
                                modelData?.triggered()
                                root.expandedIndex = -1
                            }
                        }
                    }
                }
            }

            Column {
                visible: root.entries.length === 0
                anchors.centerIn: parent
                width: Math.min(parent.width, Math.round(420 * IrisStyle.density))
                spacing: Math.round(8 * IrisStyle.density)

                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "info"
                    iconSize: Math.round(30 * IrisStyle.density)
                    color: IrisStyle.muted
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No menu actions")
                    color: IrisStyle.subtext
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeLabel
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("This application does not expose a menu.")
                    color: IrisStyle.muted
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Column {
        visible: root.items.length === 0
        anchors.centerIn: parent
        spacing: Math.round(10 * IrisStyle.density)

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "inbox"
            iconSize: Math.round(34 * IrisStyle.density)
            color: IrisStyle.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("No tray applications")
            color: IrisStyle.subtext
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeLabel
        }
    }

    // 一行菜单：分隔线、勾选/单选状态、图标、文字与子菜单箭头。
    component MenuRow: Rectangle {
        id: row

        property var entryData: null
        property bool expanded: false
        property bool nested: false
        property real indent: 0

        signal hovered()
        signal activated()

        readonly property bool isSeparator: row.entryData?.isSeparator ?? false
        readonly property bool entryEnabled: row.entryData?.enabled ?? false
        readonly property bool hasChildren: !row.nested && (row.entryData?.hasChildren ?? false)
        readonly property bool hasIcon: String(row.entryData?.icon ?? "").length > 0
        readonly property int buttonType: row.entryData?.buttonType ?? QsMenuButtonType.None
        readonly property bool checkable: buttonType === QsMenuButtonType.CheckBox
            || buttonType === QsMenuButtonType.RadioButton
        readonly property bool checked: (row.entryData?.checkState ?? Qt.Unchecked) === Qt.Checked

        height: row.isSeparator
            ? Math.round(13 * IrisStyle.density)
            : Math.round((row.nested ? 38 : 44) * IrisStyle.density)
        radius: IrisStyle.radiusSmall
        color: !row.isSeparator && rowMouse.containsMouse && row.entryEnabled
            ? IrisStyle.fillHover : "transparent"

        Rectangle {
            visible: row.isSeparator
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.round(10 * IrisStyle.density) + row.indent
            anchors.rightMargin: Math.round(10 * IrisStyle.density)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: IrisStyle.hairline
        }

        Rectangle {
            id: stateBox
            visible: row.checkable
            x: Math.round(12 * IrisStyle.density) + row.indent
            width: visible ? Math.round(14 * IrisStyle.density) : 0
            height: Math.round(14 * IrisStyle.density)
            anchors.verticalCenter: parent.verticalCenter
            radius: row.buttonType === QsMenuButtonType.RadioButton
                ? width / 2 : Math.round(3 * IrisStyle.density)
            color: "transparent"
            border.width: 1
            border.color: row.checked ? IrisStyle.accent : IrisStyle.hairline

            Rectangle {
                anchors.centerIn: parent
                visible: row.checked
                width: Math.round(6 * IrisStyle.density)
                height: width
                radius: row.buttonType === QsMenuButtonType.RadioButton
                    ? width / 2 : Math.round(1.5 * IrisStyle.density)
                color: IrisStyle.accent
            }
        }

        Image {
            id: entryIcon
            visible: row.hasIcon && !row.isSeparator
            x: stateBox.x + stateBox.width
                + (row.checkable ? Math.round(10 * IrisStyle.density) : 0)
            width: visible ? Math.round(18 * IrisStyle.density) : 0
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: row.entryData?.icon ?? ""
            sourceSize: Qt.size(36, 36)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            id: entryLabel
            visible: !row.isSeparator
            x: entryIcon.x + entryIcon.width
                + (entryIcon.visible ? Math.round(10 * IrisStyle.density) : 0)
            width: row.width - x - Math.round(12 * IrisStyle.density)
                - (row.hasChildren ? Math.round(26 * IrisStyle.density) : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: row.entryData?.text ?? ""
            color: row.entryEnabled ? IrisStyle.text : IrisStyle.muted
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeLabel
            elide: Text.ElideRight
        }

        MaterialSymbol {
            id: chevron
            visible: row.hasChildren
            anchors.right: parent.right
            anchors.rightMargin: Math.round(12 * IrisStyle.density)
            anchors.verticalCenter: parent.verticalCenter
            text: row.expanded ? "expand_more" : "chevron_right"
            iconSize: Math.round(16 * IrisStyle.density)
            color: IrisStyle.muted
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !row.isSeparator
            cursorShape: row.entryEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: row.hovered()
            onClicked: if (row.entryEnabled) row.activated()
        }
    }
}
