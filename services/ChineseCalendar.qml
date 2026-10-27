pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The whole Gregorian year of Chinese dates from one ccal call, indexed by
 * day. This is the same shape the desktop Holiday Countdown widget reads:
 * one request per year, a map of every day with its lunar month, lunar day,
 * solar term and leap-month flag.
 */
Singleton {
    id: root

    property var days: ({})
    property var requestedYears: ({})
    property var queue: []
    property string runningYear: ""
    property bool available: true

    readonly property var chineseDays: [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    function pad2(value: int): string {
        return value < 10 ? "0" + value : String(value)
    }
    function keyOf(date): string {
        if (!date) return ""
        return date.getFullYear() + "-" + root.pad2(date.getMonth() + 1) + "-" + root.pad2(date.getDate())
    }
    function forDate(date): var {
        return root.days[root.keyOf(date)] ?? null
    }
    // What the cell shows under the number: solar term first, then the lunar
    // month on its first day, then the lunar day.
    function label(date): string {
        const entry = root.forDate(date)
        if (!entry) return ""
        if (String(entry.term ?? "").length > 0) return String(entry.term)
        if (entry.d === 1) return String(entry.monthName ?? "")
        return root.chineseDays[entry.d] ?? ""
    }

    function requestYear(year: int): void {
        if (!root.available) return
        if (root.requestedYears[String(year)] || root.runningYear === String(year)) return
        if (root.queue.indexOf(year) >= 0) return
        root.queue = root.queue.concat([year])
        root.pump()
    }
    function pump(): void {
        if (ccal.running || root.queue.length === 0) return
        const year = root.queue[0]
        root.queue = root.queue.slice(1)
        root.runningYear = String(year)
        ccal.command = ["ccal", "-x", "-g", "-u", root.runningYear]
        ccal.running = true
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v ccal"]
        onExited: (exitCode) => {
            root.available = exitCode === 0
            if (root.available) root.requestYear(new Date().getFullYear())
        }
    }

    Process {
        id: ccal
        stdout: StdioCollector {
            onStreamFinished: root.parse(root.runningYear, text)
        }
        onExited: (exitCode) => {
            root.runningYear = ""
            root.pump()
        }
    }

    Component.onCompleted: probe.running = true

    function parse(year: string, output: string): void {
        if (!output || output.length === 0) return
        const next = Object.assign({}, root.days)
        const blocks = output.split(/<ccal:month\s+value="/).slice(1)
        for (const block of blocks) {
            const month = Number(block.slice(0, block.indexOf('"')))
            if (!month) continue
            const tags = /<ccal:day\s+([^>]*?)\/?>/g
            let tag
            while ((tag = tags.exec(block)) !== null) {
                const attributes = tag[1]
                const day = /value="(\d+)"/.exec(attributes)?.[1] ?? ""
                const lunarMonth = /cmonth="(\d+)"/.exec(attributes)?.[1] ?? ""
                const lunarDay = /cdate="(\d+)"/.exec(attributes)?.[1] ?? ""
                const dayName = /cdatename="([^"]*)"/.exec(attributes)?.[1] ?? ""
                const monthName = /cmonthname="([^"]*)"/.exec(attributes)?.[1] ?? ""
                const leap = /leap="([^"]*)"/.exec(attributes)?.[1] ?? ""
                if (day.length === 0 || lunarMonth.length === 0 || lunarDay.length === 0) continue
                const lunarDayNumber = Number(lunarDay)
                next[year + "-" + root.pad2(month) + "-" + root.pad2(Number(day))] = {
                    m: Number(lunarMonth),
                    d: lunarDayNumber,
                    monthName: monthName,
                    leap: leap.length > 0 && leap !== "0",
                    term: dayName === root.chineseDays[lunarDayNumber] ? "" : dayName
                }
            }
        }
        root.days = next
        root.requestedYears = Object.assign({}, root.requestedYears, { [year]: true })
    }
}
