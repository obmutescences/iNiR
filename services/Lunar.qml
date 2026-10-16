pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The Chinese calendar date of a Gregorian day, read from `ccal`.
 *
 * ccal answers one month at a time, so a single request serves every day in it and the
 * answer is kept: the Island asks on every clock tick, and a process per tick for a name
 * that changes at midnight would be waste. A missing ccal is not an error — the lunar name
 * is empty and callers keep to the Gregorian date.
 */
Singleton {
    id: root

    property bool available: false
    property var months: ({})

    // 初一…三十, indexed by the lunar day number ccal reports.
    readonly property var chineseDays: [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    // Sunday first, as Date.getDay() counts.
    readonly property var weekdayNames: ["日", "一", "二", "三", "四", "五", "六"]

    function pad2(value: int): string {
        return value < 10 ? "0" + value : String(value)
    }
    function monthKey(year: int, month: int): string {
        return year + "-" + root.pad2(month)
    }
    // The lunar day with its month ("九月-初七"), or "" while the month is still coming or
    // without ccal. The month is read per day, not per request: one Gregorian month holds
    // the tail of one lunar month and the head of the next, so 八月 and 九月 both appear in
    // October and only the day tells them apart.
    function lunarName(date): string {
        if (!date) return ""
        const month = root.months[root.monthKey(date.getFullYear(), date.getMonth() + 1)]
        const entry = month?.[String(date.getDate())]
        if (!entry) return ""
        const day = String(entry.day ?? "")
        const name = String(entry.month ?? "")
        return name.length > 0 && day.length > 0 ? name + "-" + day : day
    }
    // The weekday in Chinese ("周五"), which is the shell's own table: Qt's `ddd` follows the
    // interface language, and the date beside a Chinese lunar day reads wrong in English.
    function weekdayName(date): string {
        return date ? "周" + root.weekdayNames[date.getDay()] : ""
    }

    property var pending: []
    property string fetching: ""

    function request(date): void {
        if (!root.available || !date) return
        const key = root.monthKey(date.getFullYear(), date.getMonth() + 1)
        if (root.months[key] !== undefined || root.fetching === key || root.pending.includes(key)) return
        root.pending = root.pending.concat([key])
        root.pump()
    }
    // The month after this one, so the day name does not blink away at a month's turn.
    function requestNext(date): void {
        if (!root.available || !date) return
        root.request(new Date(date.getFullYear(), date.getMonth() + 1, 1))
    }
    function pump(): void {
        if (ccal.running || root.pending.length === 0) return
        const key = root.pending[0]
        root.pending = root.pending.slice(1)
        root.fetching = key
        const parts = key.split("-")
        ccal.requestedKey = key
        ccal.command = ["ccal", "-x", "-g", "-u", String(Number(parts[1])), parts[0]]
        ccal.running = true
    }
    function parse(key: string, output: string): void {
        if (!output) return
        const days = ({})
        // cmonthname is the month as it is written ("九月", and "闰四月" in a leap year), so
        // the shell never has to know which months are leap. cdate is the day *number*: ccal
        // puts a solar term in cdatename on the days that have one (寒露 for 廿八), which is
        // not a day name, so the table above answers for the day. Each attribute is read on
        // its own — ccal writes them in its own order, and cmonthname comes after cdate.
        const tags = /<ccal:day\s+([^>]*?)\/?>/g
        let tag
        while ((tag = tags.exec(output)) !== null) {
            const attributes = tag[1]
            const day = /value="(\d+)"/.exec(attributes)?.[1] ?? ""
            const lunarDay = /cdate="(\d+)"/.exec(attributes)?.[1] ?? ""
            if (day.length === 0 || lunarDay.length === 0) continue
            days[day] = {
                month: /cmonthname="([^"]*)"/.exec(attributes)?.[1] ?? "",
                day: root.chineseDays[Number(lunarDay)] ?? ""
            }
        }
        if (Object.keys(days).length === 0) return
        const next = Object.assign({}, root.months)
        next[key] = days
        root.months = next
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    readonly property var today: clock.date
    onTodayChanged: root.refresh()
    function refresh(): void {
        // A SystemClock hands out its date on creation, but the probe can answer first; without
        // one the month would only be asked for on the next tick, a minute later.
        const date = clock.date ?? new Date()
        root.request(date)
        root.requestNext(date)
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v ccal"]
        onExited: (exitCode) => {
            root.available = exitCode === 0
            if (root.available) root.refresh()
        }
    }
    Process {
        id: ccal
        property string requestedKey: ""
        command: []
        stdout: StdioCollector { id: ccalOut }
        onExited: (exitCode) => {
            if (exitCode === 0) root.parse(ccal.requestedKey, ccalOut.text)
            root.fetching = ""
            root.pump()
        }
    }

    Component.onCompleted: probe.running = true
}
