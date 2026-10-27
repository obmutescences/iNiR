pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Statutory holiday schedule (official days off and make-up workdays) from the
 * government notices mirrored by the holiday-cn project. One small JSON fetch
 * per year, kept in memory for the lifetime of the shell.
 */
Singleton {
    id: root

    property var days: ({})
    property var requestedYears: ({})
    property var queue: []
    property string runningYear: ""

    function pad2(value: int): string {
        return value < 10 ? "0" + value : String(value)
    }
    function keyOf(date): string {
        if (!date) return ""
        return date.getFullYear() + "-" + root.pad2(date.getMonth() + 1) + "-" + root.pad2(date.getDate())
    }
    function info(date): var {
        return root.days[root.keyOf(date)] ?? null
    }

    function requestYear(year: int): void {
        if (root.requestedYears[String(year)] || root.runningYear === String(year)) return
        if (root.queue.indexOf(year) >= 0) return
        root.queue = root.queue.concat([year])
        root.pump()
    }
    function pump(): void {
        if (fetch.running || root.queue.length === 0) return
        const year = root.queue[0]
        root.queue = root.queue.slice(1)
        root.runningYear = String(year)
        fetch.command = ["curl", "-fsSL", "--max-time", "15",
            "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/" + root.runningYear + ".json"]
        fetch.running = true
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: root.parse(root.runningYear, text)
        }
        onExited: (exitCode) => {
            // A failed year (not published yet) is not retried until the next shell start.
            root.requestedYears = Object.assign({}, root.requestedYears, { [root.runningYear]: true })
            root.runningYear = ""
            root.pump()
        }
    }

    function parse(year: string, output: string): void {
        if (!output || output.length === 0) return
        let data
        try {
            data = JSON.parse(output)
        } catch (error) {
            return
        }
        if (!data || !Array.isArray(data.days)) return
        const next = Object.assign({}, root.days)
        for (const item of data.days) {
            if (!item?.date) continue
            next[String(item.date)] = { name: String(item.name ?? ""), off: item.isOffDay === true }
        }
        root.days = next
    }
}
