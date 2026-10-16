pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Throughput in bytes per second, sampled from /proc/net/dev.
 *
 * Every interface except loopback is summed: the reading is what the machine is doing, not
 * what one link is doing. Sampling runs only while something reads it (NetSpeedMonitor), so
 * a shell without the bubble pays nothing for it.
 */
Singleton {
    id: root

    property real downloadRate: 0
    property real uploadRate: 0
    property int readers: 0
    property real _lastReceived: -1
    property real _lastTransmitted: -1
    property double _lastSampleTime: 0

    function keepAlive(): void {
        root.readers += 1
    }
    function releaseKeepAlive(): void {
        root.readers = Math.max(0, root.readers - 1)
    }

    // The rate as the face reads it: whole kilobytes at the floor, whole megabytes from 1 MB up.
    // One letter carries the unit, and both letters are the same width, so a rate crossing 1 MB
    // does not move the piece.
    function rateParts(raw): var {
        const whole = Math.round(Math.max(0, Number(raw) || 0) / 1024)
        return whole >= 1024
            ? ({ value: String(Math.round(whole / 1024)), unit: "M" })
            : ({ value: String(whole), unit: "K" })
    }

    function sample(contents): void {
        let received = 0
        let transmitted = 0
        const lines = String(contents).split("\n")
        for (const line of lines) {
            const separator = line.indexOf(":")
            if (separator < 0)
                continue
            const name = line.slice(0, separator).trim()
            if (name.length === 0 || name === "lo")
                continue
            const fields = line.slice(separator + 1).trim().split(/\s+/)
            if (fields.length < 9)
                continue
            const rx = Number(fields[0])
            const tx = Number(fields[8])
            if (!Number.isFinite(rx) || !Number.isFinite(tx))
                continue
            received += rx
            transmitted += tx
        }

        const now = Date.now()
        if (root._lastSampleTime > 0 && now > root._lastSampleTime) {
            const elapsed = now - root._lastSampleTime
            root.downloadRate = (received >= root._lastReceived ? received - root._lastReceived : 0) * 1000 / elapsed
            root.uploadRate = (transmitted >= root._lastTransmitted ? transmitted - root._lastTransmitted : 0) * 1000 / elapsed
        }
        root._lastReceived = received
        root._lastTransmitted = transmitted
        root._lastSampleTime = now
    }

    FileView {
        id: netStats
        path: "/proc/net/dev"
        printErrors: false
        blockLoading: true
        onLoaded: root.sample(netStats.text())
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.readers > 0
        onTriggered: netStats.reload()
    }
}
