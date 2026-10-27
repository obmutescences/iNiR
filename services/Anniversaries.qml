pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * User anniversaries, solar or lunar. The desktop Holiday Countdown widget's
 * annual list is the primary source; the panel's own file is a fallback.
 *
 * Each item:
 *   { "name": "生日", "calendar": "lunar", "month": 8, "day": 15 }
 *   { "title": "结婚纪念日", "calendar": "solar", "date": "2020-05-20", "yearly": true }
 *
 * Lunar items need a Gregorian date, which ccal only answers in the
 * Gregorian -> lunar direction. The whole year is read once and indexed by
 * lunar month/day, the same external tool the shell already uses for Lunar.
 */
Singleton {
    id: root

    property var raw: []
    property var today: DateTime.clock.date
    readonly property int year: root.today ? root.today.getFullYear() : new Date().getFullYear()
    property int lunarYear: 0
    property var lunarIndex: ({})
    property bool lunarReady: false
    property var upcoming: []
    property bool loaded: false

    // The desktop Holiday Countdown widget keeps the user's anniversaries here;
    // the panel reads the same file so both surfaces agree.
    readonly property string widgetPath: Directories.configPath + "/inir/widgets/holiday-countdown/anniversaries.json"
    readonly property string fallbackPath: Directories.stateUserPath + "/center-panel/anniversaries.json"
    property string filePath: root.widgetPath


    function pad2(value: int): string {
        return value < 10 ? "0" + value : String(value)
    }
    function dayKey(date): string {
        return date.getFullYear() + "-" + root.pad2(date.getMonth() + 1) + "-" + root.pad2(date.getDate())
    }
    function startOfDay(date): var {
        const copy = new Date(date)
        copy.setHours(0, 0, 0, 0)
        return copy
    }
    function daysBetween(from, to): int {
        return Math.round((root.startOfDay(to).getTime() - root.startOfDay(from).getTime()) / 86400000)
    }

    function load(): void {
        anniversariesFile.reload()
    }

    FileView {
        id: anniversariesFile
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        printErrors: false
        onLoaded: {
            const text = anniversariesFile.text()
            if (!text || text.trim().length === 0) {
                root.raw = []
                root.loaded = true
                root.compute()
                return
            }
            try {
                const parsed = JSON.parse(text)
                root.raw = Array.isArray(parsed) ? parsed : (parsed.anniversaries ?? parsed.items ?? [])
            } catch (e) {
                console.warn("[Anniversaries] Failed to parse:", e)
                root.raw = []
            }
            root.loaded = true
            root.compute()
        }
        onLoadFailed: (error) => {
            if (root.filePath !== root.fallbackPath) {
                root.filePath = root.fallbackPath
                reload()
                return
            }
            root.raw = []
            root.loaded = true
            if (error !== FileViewError.FileNotFound)
                console.warn("[Anniversaries] Failed to load:", error)
            root.compute()
        }
    }

    // One ccal call per Gregorian year, indexed by lunar month name and day.
    Process {
        id: lunarCurrent
        command: ["ccal", "-x", "-g", "-u", String(root.year)]
        stdout: StdioCollector {
            onStreamFinished: root.parseLunar(text, root.year)
        }
    }
    Process {
        id: lunarNext
        command: ["ccal", "-x", "-g", "-u", String(root.year + 1)]
        stdout: StdioCollector {
            onStreamFinished: root.parseLunar(text, root.year + 1)
        }
    }

    function requestLunar(): void {
        root.lunarYear = root.year
        if (!lunarCurrent.running) lunarCurrent.running = true
        if (!lunarNext.running) lunarNext.running = true
    }

    function parseLunar(output: string, year: int): void {
        if (!output || output.length === 0) return
        const index = Object.assign({}, root.lunarIndex)
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
                const leap = /leap="([^"]*)"/.exec(attributes)?.[1] ?? ""
                if (day.length === 0 || lunarMonth.length === 0 || lunarDay.length === 0) continue
                if (leap.length > 0 && leap !== "0") continue
                index[year + "|" + Number(lunarMonth) + "|" + Number(lunarDay)]
                    = year + "-" + root.pad2(month) + "-" + root.pad2(Number(day))
            }
        }
        root.lunarIndex = index
        root.lunarReady = true
        root.compute()
    }

    function solarOccurrence(item): var {
        if (item.date) {
            const parts = String(item.date).split("-").map(Number)
            if (parts.length !== 3 || parts.some(isNaN)) return null
            const yearly = item.yearly !== false
            if (!yearly) {
                const exact = new Date(parts[0], parts[1] - 1, parts[2])
                return exact >= root.startOfDay(root.today) ? exact : null
            }
            let next = new Date(root.year, parts[1] - 1, parts[2])
            if (next < root.startOfDay(root.today)) next = new Date(root.year + 1, parts[1] - 1, parts[2])
            return next
        }
        const month = Number(item.month)
        const day = Number(item.day)
        if (!month || !day) return null
        let next = new Date(root.year, month - 1, day)
        if (next < root.startOfDay(root.today)) next = new Date(root.year + 1, month - 1, day)
        return next
    }

    function lunarOccurrence(item): var {
        const month = Number(item.month)
        const day = Number(item.day)
        if (!month || !day) return null
        const today = root.startOfDay(root.today)
        for (const year of [root.year, root.year + 1]) {
            let key = year + "|" + month + "|" + day
            if (!root.lunarIndex[key] && day === 30)
                key = year + "|" + month + "|29"
            const value = root.lunarIndex[key]
            if (!value) continue
            const parts = value.split("-").map(Number)
            const date = new Date(parts[0], parts[1] - 1, parts[2])
            if (date >= today) return date
        }
        return null
    }

    function compute(): void {
        const out = []
        for (const item of root.raw) {
            if (!item || (!item.title && !item.name)) continue
            const lunar = String(item.calendar ?? "solar") === "lunar"
            const date = lunar ? root.lunarOccurrence(item) : root.solarOccurrence(item)
            if (!date) continue
            out.push({
                title: String(item.title ?? item.name ?? ""),
                calendar: lunar ? "lunar" : "solar",
                date: date,
                days: root.daysBetween(root.today, date),
                note: String(item.note ?? "")
            })
        }
        out.sort((a, b) => a.date - b.date)
        root.upcoming = out
    }

    function forMonth(year: int, month: int): var {
        return root.upcoming.filter(entry =>
            entry.date.getFullYear() === year && entry.date.getMonth() + 1 === month)
    }
    function forDay(date): var {
        const key = root.dayKey(date)
        return root.upcoming.filter(entry => root.dayKey(entry.date) === key)
    }

    onTodayChanged: {
        root.compute()
        if (root.year !== root.lunarYear) root.requestLunar()
    }
    Component.onCompleted: {
        root.load()
        root.requestLunar()
    }
}
