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
    property int monthShift: 0
    property var selectedDate: null

    readonly property date today: DateTime.clock.date
    readonly property date viewingDate: new Date(root.today.getFullYear(), root.today.getMonth() + root.monthShift, 1)
    readonly property int viewYear: root.viewingDate.getFullYear()
    readonly property int viewMonth: root.viewingDate.getMonth()
    readonly property int weekStart: 1
    readonly property real footerHeight: {
        const list = root.selectedDate ? root.selectedAnniversaries : root.monthAnniversaries
        return (root.selectedDate !== null || list.length > 0) ? Math.round(92 * IrisStyle.density) : 0
    }

    readonly property var cells: {
        const year = root.viewYear
        const month = root.viewMonth
        const first = new Date(year, month, 1)
        const offset = (first.getDay() - root.weekStart + 7) % 7
        const daysInMonth = new Date(year, month + 1, 0).getDate()
        const daysInPrev = new Date(year, month, 0).getDate()
        const out = []
        for (let i = offset - 1; i >= 0; --i)
            out.push({ date: new Date(year, month - 1, daysInPrev - i), current: false })
        for (let d = 1; d <= daysInMonth; ++d)
            out.push({ date: new Date(year, month, d), current: true })
        let next = 1
        while (out.length < 42)
            out.push({ date: new Date(year, month + 1, next++), current: false })
        return out
    }
    readonly property var weekDayNames: {
        const names = []
        const base = ["日", "一", "二", "三", "四", "五", "六"]
        for (let i = 0; i < 7; ++i) names.push(base[(root.weekStart + i) % 7])
        return names
    }
    readonly property int weekNumber: {
        const date = new Date(Date.UTC(root.viewYear, root.viewMonth, 1))
        const day = date.getUTCDay() || 7
        date.setUTCDate(date.getUTCDate() + 4 - day)
        const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
        return Math.ceil((((date - yearStart) / 86400000) + 1) / 7)
    }
    readonly property var monthAnniversaries: Anniversaries.forMonth(root.viewYear, root.viewMonth + 1)
    readonly property var selectedAnniversaries: root.selectedDate ? Anniversaries.forDay(root.selectedDate) : []
    readonly property string selectedFestival: root.selectedDate ? root.festivalFor(root.selectedDate) : ""
    readonly property var footerList: {
        const list = root.selectedDate ? root.selectedAnniversaries : root.monthAnniversaries
        return list.slice(0, 4)
    }


    function sameDate(a, b): bool {
        return !!a && !!b && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function festivalFor(date): string {
        if (!date) return ""
        const month = date.getMonth() + 1
        const day = date.getDate()
        if (month === 1 && day === 1) return "元旦"
        if (month === 5 && day === 1) return "劳动节"
        if (month === 10 && day === 1) return "国庆"
        const lunar = ChineseCalendar.forDate(date)
        if (!lunar) return ""
        if (lunar.term === "清明") return "清明"
        if (lunar.leap || lunar.term) return ""
        if (lunar.m === 1 && lunar.d === 1) return "春节"
        if (lunar.m === 5 && lunar.d === 5) return "端午"
        if (lunar.m === 8 && lunar.d === 15) return "中秋"
        return ""
    }
    function cellLabel(date): string {
        const festival = root.festivalFor(date)
        if (festival.length > 0) return festival
        return ChineseCalendar.label(date)
    }
    function select(date): void {
        root.selectedDate = date
    }
    function goToday(): void {
        root.monthShift = 0
    }

    onViewYearChanged: {
        ChineseCalendar.requestYear(root.viewYear)
        ChineseCalendar.requestYear(root.viewYear + 1)
        HolidayCalendar.requestYear(root.viewYear)
        HolidayCalendar.requestYear(root.viewYear + 1)
    }
    Component.onCompleted: {
        ChineseCalendar.requestYear(root.viewYear)
        ChineseCalendar.requestYear(root.viewYear + 1)
        HolidayCalendar.requestYear(root.viewYear)
        HolidayCalendar.requestYear(root.viewYear + 1)
    }

    Column {
        anchors.fill: parent
        spacing: Math.round(10 * IrisStyle.density)

        Item {
            id: header
            width: parent.width
            height: Math.round(44 * IrisStyle.density)

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(8 * IrisStyle.density)
                Text {
                    text: root.viewYear + "年 " + (root.viewMonth + 1) + "月"
                    color: IrisStyle.text
                    font.family: IrisStyle.fontMain
                    font.pixelSize: Math.round(26 * IrisStyle.density)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "第 " + root.weekNumber + " 周"
                    color: IrisStyle.subtext
                    font.family: IrisStyle.fontMain
                    font.pixelSize: IrisStyle.typeFootnote
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(6 * IrisStyle.density)

                IrisIconButton {
                    materialIcon: "chevron_left"
                    onClicked: root.monthShift -= 1
                }
                Rectangle {
                    width: todayLabel.implicitWidth + Math.round(24 * IrisStyle.density)
                    height: Math.round(34 * IrisStyle.density)
                    radius: height / 2
                    color: todayHover.hovered ? IrisStyle.fillHover : IrisStyle.fill
                    Text {
                        id: todayLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Today")
                        color: IrisStyle.text
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeLabel
                    }
                    HoverHandler { id: todayHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToday()
                    }
                }
                IrisIconButton {
                    materialIcon: "chevron_right"
                    onClicked: root.monthShift += 1
                }
            }
        }

        Row {
            id: weekRow
            width: parent.width
            height: Math.round(22 * IrisStyle.density)
            Repeater {
                model: root.weekDayNames
                Item {
                    required property var modelData
                    width: weekRow.width / 7
                    height: weekRow.height
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                }
            }
        }

        Rectangle {
            id: calendarBody
            width: parent.width
            height: parent.height - header.height - weekRow.height - root.footerHeight
                - Math.round(30 * IrisStyle.density)
            radius: IrisStyle.radiusCard
            color: IrisStyle.fill
            border.width: 1
            border.color: IrisStyle.hairline
            antialiasing: true

            Grid {
                anchors.fill: parent
                anchors.margins: 1
                columns: 7
                rows: 6

                Repeater {
                    model: root.cells

                    Rectangle {
                        id: dayCell
                        required property var modelData
                        readonly property date cellDate: dayCell.modelData.date
                        readonly property bool current: dayCell.modelData.current
                        readonly property bool isToday: root.sameDate(dayCell.cellDate, root.today)
                        readonly property bool isSelected: root.sameDate(dayCell.cellDate, root.selectedDate)
                        readonly property string label: root.cellLabel(dayCell.cellDate)
                        readonly property bool hasFestival: root.festivalFor(dayCell.cellDate).length > 0
                        readonly property var anniversaryList: Anniversaries.forDay(dayCell.cellDate)
                        readonly property int anniversaries: dayCell.anniversaryList.length
                        readonly property string anniversaryLabel: dayCell.anniversaryList.length === 0 ? ""
                            : String(dayCell.anniversaryList[0].title)
                                + (dayCell.anniversaryList.length > 1 ? " +" + (dayCell.anniversaryList.length - 1) : "")
                        readonly property var holiday: HolidayCalendar.info(dayCell.cellDate)

                        width: calendarBody.width / 7
                        height: calendarBody.height / 6
                        radius: IrisStyle.radiusTile
                        color: dayCell.isSelected ? IrisStyle.fillHover
                            : dayCell.isToday ? IrisStyle.fill
                            : dayCellMouse.hovered ? IrisStyle.fill : "transparent"
                        border.width: dayCell.isToday ? 1 : 0
                        border.color: IrisStyle.accent

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: Math.round(10 * IrisStyle.density)
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCell.cellDate.getDate()
                            color: !dayCell.current ? IrisStyle.muted
                                : dayCell.isToday ? IrisStyle.accent : IrisStyle.text
                            font.family: IrisStyle.fontNumbers
                            font.pixelSize: Math.round(17 * IrisStyle.density)
                            font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                        }
                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: Math.round(34 * IrisStyle.density)
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - Math.round(6 * IrisStyle.density)
                            text: dayCell.label
                            horizontalAlignment: Text.AlignHCenter
                            color: dayCell.hasFestival ? IrisStyle.accent : IrisStyle.subtext
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeCaption
                            elide: Text.ElideRight
                        }
                        Row {
                            anchors.top: parent.top
                            anchors.topMargin: Math.round(54 * IrisStyle.density)
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Math.round(4 * IrisStyle.density)

                            Text {
                                visible: dayCell.holiday !== null
                                text: (dayCell.holiday?.off ?? false) ? "休" : "班"
                                color: (dayCell.holiday?.off ?? false) ? IrisStyle.success : IrisStyle.warning
                                opacity: dayCell.current ? 1 : 0.45
                                font.family: IrisStyle.fontMain
                                font.pixelSize: IrisStyle.typeCaption
                                font.weight: Font.DemiBold
                            }
                            Text {
                                visible: dayCell.anniversaryLabel.length > 0
                                width: Math.min(implicitWidth, dayCell.width - Math.round(16 * IrisStyle.density)
                                    - (dayCell.holiday !== null ? Math.round(18 * IrisStyle.density) : 0))
                                text: dayCell.anniversaryLabel
                                color: IrisStyle.secondaryAccent
                                opacity: dayCell.current ? 1 : 0.45
                                font.family: IrisStyle.fontMain
                                font.pixelSize: IrisStyle.typeCaption
                                elide: Text.ElideRight
                            }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.round(9 * IrisStyle.density)
                            spacing: 3
                            Repeater {
                                model: Math.min(3, dayCell.anniversaries)
                                Rectangle {
                                    width: Math.round(5 * IrisStyle.density)
                                    height: width
                                    radius: width / 2
                                    color: IrisStyle.secondaryAccent
                                }
                            }
                        }

                        HoverHandler { id: dayCellMouse }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.select(dayCell.cellDate)
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            width: parent.width
            height: root.footerHeight
            visible: root.footerHeight > 0

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.selectedDate
                    ? (root.selectedDate.getFullYear() + "年" + (root.selectedDate.getMonth() + 1) + "月"
                        + root.selectedDate.getDate() + "日")
                    : Translation.tr("This month")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
            }

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: Math.round(20 * IrisStyle.density)
                visible: root.selectedFestival.length > 0 && root.selectedDate !== null
                text: root.selectedFestival
                color: IrisStyle.accent
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeLabel
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Math.round(34 * IrisStyle.density)
                spacing: Math.round(10 * IrisStyle.density)

                Repeater {
                    model: root.footerList

                    Item {
                        required property var modelData
                        width: (footer.width - Math.round(10 * IrisStyle.density) * 3) / 4
                        height: Math.round(48 * IrisStyle.density)

                        Rectangle {
                            anchors.fill: parent
                            radius: IrisStyle.radiusSmall
                            color: IrisStyle.fill
                            border.width: 1
                            border.color: IrisStyle.hairline
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(10 * IrisStyle.density)
                            anchors.right: parent.right
                            anchors.rightMargin: Math.round(10 * IrisStyle.density)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                width: parent.width
                                text: modelData.title
                                color: IrisStyle.text
                                font.family: IrisStyle.fontMain
                                font.pixelSize: IrisStyle.typeFootnote
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: (modelData.date.getMonth() + 1) + "月" + modelData.date.getDate() + "日"
                                    + " · " + (modelData.days === 0
                                        ? Translation.tr("Today")
                                        : Translation.tr("in %1 days").arg(modelData.days))
                                color: IrisStyle.subtext
                                font.family: IrisStyle.fontNumbers
                                font.pixelSize: IrisStyle.typeCaption
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: Math.round(34 * IrisStyle.density)
                visible: root.footerList.length === 0
                text: Translation.tr("No anniversaries this month")
                color: IrisStyle.muted
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeFootnote
            }
        }
    }
}
