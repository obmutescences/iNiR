pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The network details the speed gauge cannot answer: latency, loss, link
 * speed and the bytes moved while the panel has been open. The interface and
 * gateway come from the default route; ping talks to that gateway so the
 * number measures the local link, not a remote DNS server.
 */
Singleton {
    id: root

    property bool active: false
    property string iface: ""
    property string gateway: ""
    property real latencyMs: -1
    property real lossPercent: -1
    property real linkSpeedMbps: -1
    property real rxBytes: 0
    property real txBytes: 0
    property real rxBase: -1
    property real txBase: -1
    property int sampleMs: 2000

    readonly property string ifaceLabel: root.iface.length > 0 ? root.iface : "-"
    readonly property string linkLabel: root.linkSpeedMbps > 0
        ? (root.linkSpeedMbps >= 1000 ? (root.linkSpeedMbps / 1000).toFixed(1) + " Gbps"
                                      : Math.round(root.linkSpeedMbps) + " Mbps")
        : ""

    function hexToIp(hex: string): string {
        const value = parseInt(hex, 16)
        if (isNaN(value)) return ""
        return [value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255].join(".")
    }

    FileView {
        id: route
        path: "/proc/net/route"
        blockLoading: true
        printErrors: false
        onLoaded: root.parseRoute(route.text())
    }

    FileView {
        id: speed
        path: root.iface.length > 0 ? "/sys/class/net/" + root.iface + "/speed" : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            const value = Number(speed.text().trim())
            root.linkSpeedMbps = isFinite(value) && value > 0 ? value : -1
        }
        onLoadFailed: root.linkSpeedMbps = -1
    }

    FileView {
        id: dev
        path: "/proc/net/dev"
        blockLoading: true
        printErrors: false
        onLoaded: root.parseDev(dev.text())
    }

    function parseRoute(text: string): void {
        for (const line of text.split("\n")) {
            const fields = line.trim().split(/\s+/)
            if (fields.length < 4 || fields[1] !== "00000000") continue
            root.iface = fields[0]
            root.gateway = root.hexToIp(fields[2])
            return
        }
    }

    function parseDev(text: string): void {
        if (root.iface.length === 0) return
        for (const line of text.split("\n")) {
            const trimmed = line.trim()
            if (!trimmed.startsWith(root.iface + ":")) continue
            const fields = trimmed.slice(trimmed.indexOf(":") + 1).trim().split(/\s+/)
            if (fields.length < 9) return
            const rx = Number(fields[0])
            const tx = Number(fields[8])
            if (isNaN(rx) || isNaN(tx)) return
            if (root.rxBase < 0) {
                root.rxBase = rx
                root.txBase = tx
            }
            root.rxBytes = Math.max(0, rx - root.rxBase)
            root.txBytes = Math.max(0, tx - root.txBase)
            return
        }
    }

    Process {
        id: pinger
        command: root.gateway.length > 0
            ? ["ping", "-c", "3", "-W", "1", "-q", root.gateway]
            : ["sh", "-c", "exit 1"]
        stdout: StdioCollector {
            onStreamFinished: root.parsePing(text)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.latencyMs = -1
                root.lossPercent = -1
            }
        }
    }

    function parsePing(text: string): void {
        if (!text || text.length === 0) return
        const loss = /(\d+(?:\.\d+)?)% packet loss/.exec(text)
        if (loss) root.lossPercent = Number(loss[1])
        const rtt = /=\s*[\d.]+\/([\d.]+)\/[\d.]+\/[\d.]+\s*ms/.exec(text)
        if (rtt) root.latencyMs = Number(rtt[1])
    }

    Timer {
        interval: 5000
        running: root.active && root.gateway.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!pinger.running) pinger.running = true
    }

    Timer {
        interval: root.sampleMs
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: dev.reload()
    }

    onActiveChanged: {
        if (root.active) {
            route.reload()
            dev.reload()
        } else {
            root.rxBase = -1
            root.txBase = -1
            root.rxBytes = 0
            root.txBytes = 0
            root.latencyMs = -1
            root.lossPercent = -1
        }
    }

    Component.onCompleted: route.reload()
}
