pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Top processes for the center panel, sampled from one batch `top` call.
 * Only runs while the panel's process page is on screen: a hidden panel must
 * not spawn a sampler every two seconds.
 */
Singleton {
    id: root

    property bool active: false
    property bool paused: false
    property int refreshMs: 2000
    property var processes: []
    property int total: -1
    property string sortBy: "cpu" // cpu | memory

    readonly property var sorted: {
        const list = root.processes.slice()
        list.sort((a, b) => root.sortBy === "memory" ? b.memory - a.memory : b.cpu - a.cpu)
        return list
    }

    function refresh(): void {
        if (!root.active || root.paused || sampler.running) return
        sampler.running = true
    }
    function togglePaused(): void {
        root.paused = !root.paused
        if (!root.paused) root.refresh()
    }

    onPausedChanged: if (root.paused) sampler.running = false
    onActiveChanged: {
        if (root.active) root.refresh()
        else {
            sampler.running = false
            root.paused = false
        }
    }

    Timer {
        interval: root.refreshMs
        running: root.active && !root.paused
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: sampler
        command: ["sh", "-c", "top -b -n 1 -w 512 -o %CPU 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    function parse(output: string): void {
        if (root.paused || !output || output.length === 0) return
        const list = []
        let total = -1
        for (const line of output.split("\n")) {
            const tasks = /^Tasks:\s+(\d+)\s+total/.exec(line)
            if (tasks) {
                total = Number(tasks[1])
                continue
            }
            const fields = line.trim().split(/\s+/)
            if (fields.length < 12 || fields[0] === "PID") continue
            const pid = Number(fields[0])
            if (!pid || isNaN(pid)) continue
            const cpu = Number(fields[8])
            const memoryKb = Number(fields[5])
            if (isNaN(cpu) || isNaN(memoryKb)) continue
            list.push({
                pid: pid,
                name: fields.slice(11).join(" "),
                cpu: cpu,
                memory: memoryKb / 1048576
            })
        }
        root.processes = list
        if (total >= 0) root.total = total
    }

    function killProcess(pid: int): void {
        if (!pid || pid <= 0) return
        Quickshell.execDetached(["kill", String(pid)])
        root.processes = root.processes.filter(entry => entry.pid !== pid)
    }
}
