pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
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
    property bool _held: false
    readonly property real gap: Math.round(14 * IrisStyle.density)
    readonly property real cardRadius: IrisStyle.radiusCard
    readonly property color cpuTint: ResourceUsage.cpuUsage >= 0.9 ? IrisStyle.danger : IrisStyle.accent
    readonly property color memoryTint: ResourceUsage.memoryUsedPercentage >= 0.9 ? IrisStyle.danger : IrisStyle.secondaryAccent
    readonly property color gpuTint: IrisStyle.identity.purple
    readonly property color diskTint: IrisStyle.success

    readonly property real diskRatio: root.diskTotalBytes > 0
        ? root.diskUsedBytes / root.diskTotalBytes : ResourceUsage.diskUsedPercentage
    readonly property real downloadRate: Math.max(0, NetSpeed.downloadRate)
    readonly property real uploadRate: Math.max(0, NetSpeed.uploadRate)
    readonly property real downloadShare: Math.min(1, root.downloadRate / (5 * 1048576))
    readonly property real uploadShare: Math.min(1, root.uploadRate / (2 * 1048576))
    readonly property var loadParts: root.loadText.trim().split(/\s+/)
    readonly property real loadOne: Number(root.loadParts[0] ?? 0)
    readonly property real loadFive: Number(root.loadParts[1] ?? 0)

    property string loadText: ""
    property real diskTotalBytes: 0
    property real diskUsedBytes: 0

    function memoryText(kb): string {
        const mib = Number(kb) / 1024
        if (mib >= 1024) return (mib / 1024).toFixed(1) + " GB"
        return Math.round(mib) + " MB"
    }
    function trafficText(bytes): string {
        const value = Number(bytes)
        if (!isFinite(value) || value <= 0) return "0 MB"
        if (value >= 1073741824) return (value / 1073741824).toFixed(2) + " GB"
        return (value / 1048576).toFixed(1) + " MB"
    }
    function rateParts(raw): var {
        const value = Math.max(0, Number(raw) || 0)
        if (value >= 1048576) return { value: (value / 1048576).toFixed(2), unit: "MB/s" }
        if (value >= 1024) return { value: String(Math.round(value / 1024)), unit: "KB/s" }
        return { value: String(Math.round(value)), unit: "B/s" }
    }
    function coreCount(): int {
        return ResourceUsage.cpuCoreUsage.length
    }
    function refreshLoad(): void {
        loadFile.reload()
    }
    function refreshDisk(): void {
        if (root.active && !diskProc.running) diskProc.running = true
    }

    readonly property bool weatherReady: Weather.hasData
    readonly property var forecastDays: (Weather.data?.forecast ?? []).slice(0, 5)
    readonly property var hourlySlots: (Weather.data?.hourly ?? []).slice(0, 6)
    readonly property real tempLow: {
        let value = Infinity
        for (const day of root.forecastDays) {
            const low = Number(day.loVal)
            if (isFinite(low)) value = Math.min(value, low)
        }
        return isFinite(value) ? value : 0
    }
    readonly property real tempHigh: {
        let value = -Infinity
        for (const day of root.forecastDays) {
            const high = Number(day.hiVal)
            if (isFinite(high)) value = Math.max(value, high)
        }
        return isFinite(value) ? value : 1
    }
    readonly property real tempSpan: Math.max(1, root.tempHigh - root.tempLow)

    function tempLabel(text): string {
        return String(text ?? "").replace("°C", "°").replace("°F", "°")
    }

    Component.onCompleted: {
        if (root.active && !root._held) {
            NetSpeed.keepAlive()
            root._held = true
        }
        NetworkDetails.active = root.active
        root.refreshLoad()
    }
    onActiveChanged: {
        NetworkDetails.active = root.active
        if (root.active && !root._held) {
            NetSpeed.keepAlive()
            root._held = true
            root.refreshLoad()
        } else if (!root.active && root._held) {
            NetSpeed.releaseKeepAlive()
            root._held = false
        }
    }
    Component.onDestruction: {
        if (root._held) NetSpeed.releaseKeepAlive()
        NetworkDetails.active = false
    }

    // 面板自己持有采样：岛的 usage 组件关掉时，CPU/内存也要有数据。
    // 页面收起后自动释放，服务由 autoStopTimer 停掉。
    ResourceUsageMonitor {
        target: root
    }

    Timer {
        interval: 5000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshLoad()
            root.refreshDisk()
        }
    }

    FileView {
        id: loadFile
        path: "/proc/loadavg"
        blockLoading: true
        printErrors: false
        onLoaded: root.loadText = loadFile.text()
    }

    Process {
        id: diskProc
        command: ["sh", "-c", "df -B1 / 2>/dev/null | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(/\s+/)
                if (fields.length < 3) return
                root.diskTotalBytes = Number(fields[1]) || 0
                root.diskUsedBytes = Number(fields[2]) || 0
            }
        }
    }

    readonly property real topHeight: Math.round(250 * IrisStyle.density)

    Row {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.topHeight
        spacing: root.gap

        LiquidCard {
            width: (topRow.width - root.gap * 3) / 4
            height: topRow.height
            radius: root.cardRadius
            title: Translation.tr("CPU")
            value: ResourceUsage.cpuUsage
            figure: String(Math.round(ResourceUsage.cpuUsage * 100))
            detail: root.coreCount() + " " + Translation.tr("cores")
                + (ResourceUsage.cpuFrequencyMhz > 0
                    ? " · " + (ResourceUsage.cpuFrequencyMhz / 1000).toFixed(2) + " GHz" : "")
            badge: ResourceUsage.cpuTemp > 0 ? ResourceUsage.cpuTemp + " °C" : ""
            tint: root.cpuTint
            animating: root.active
        }
        LiquidCard {
            width: (topRow.width - root.gap * 3) / 4
            height: topRow.height
            radius: root.cardRadius
            title: Translation.tr("Memory")
            value: ResourceUsage.memoryUsedPercentage
            figure: String(Math.round(ResourceUsage.memoryUsedPercentage * 100))
            detail: root.memoryText(ResourceUsage.memoryUsed) + " / "
                + root.memoryText(ResourceUsage.memoryTotal) + " · Swap "
                + root.memoryText(ResourceUsage.swapUsed)
            tint: root.memoryTint
            animating: root.active
        }
        // 与官方桌面组件一致：取 ResourceUsage 的 GPU 读数（sysfs / nvidia-smi / intel_gpu_top）。
        LiquidCard {
            width: (topRow.width - root.gap * 3) / 4
            height: topRow.height
            radius: root.cardRadius
            title: Translation.tr("GPU")
            value: ResourceUsage.gpuUsage
            figure: String(Math.round(ResourceUsage.gpuUsage * 100))
            detail: ResourceUsage.gpuMemoryUsedGb >= 0 && ResourceUsage.gpuMemoryTotalGb > 0
                ? ResourceUsage.gpuMemoryUsedGb.toFixed(1) + " / "
                    + ResourceUsage.gpuMemoryTotalGb.toFixed(1) + " GB" : ""
            badge: ResourceUsage.gpuTemp > 0 ? ResourceUsage.gpuTemp + " °C" : ""
            tint: root.gpuTint
            animating: root.active
        }
        LiquidCard {
            width: (topRow.width - root.gap * 3) / 4
            height: topRow.height
            radius: root.cardRadius
            title: Translation.tr("Disk")
            value: root.diskRatio
            figure: String(Math.round(root.diskRatio * 100))
            detail: ((root.diskTotalBytes > 0 ? root.diskUsedBytes : ResourceUsage.diskUsed) / 1073741824).toFixed(0)
                + " / " + ((root.diskTotalBytes > 0 ? root.diskTotalBytes : ResourceUsage.diskTotal) / 1073741824).toFixed(0) + " GB"
            tint: root.diskTint
            animating: root.active
        }
    }

    Rectangle {
        id: networkCard
        anchors.left: parent.left
        anchors.top: topRow.bottom
        anchors.topMargin: root.gap
        anchors.bottom: parent.bottom
        width: (parent.width - root.gap) / 2
        radius: root.cardRadius
        color: IrisStyle.fill
        border.width: 1
        border.color: IrisStyle.hairline
        antialiasing: true

        Item {
            anchors.fill: parent
            anchors.margins: Math.round(20 * IrisStyle.density)

            Text {
                id: networkTitle
                text: Translation.tr("Network")
                color: IrisStyle.text
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeHeadline
                font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                text: NetworkDetails.ifaceLabel + (NetworkDetails.linkLabel.length > 0
                    ? " · " + NetworkDetails.linkLabel : "")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontNumbers
                font.pixelSize: IrisStyle.typeFootnote
            }

            Item {
                id: gauges
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: networkTitle.bottom
                anchors.topMargin: Math.round(10 * IrisStyle.density)
                anchors.bottom: parent.bottom

                readonly property real infoWidth: Math.round(150 * IrisStyle.density)
                readonly property real gaugeWidth: Math.max(40, (width - infoWidth - root.gap * 2) / 2)

                RadialGauge {
                    x: 0
                    width: gauges.gaugeWidth
                    height: Math.min(gauges.height, Math.round(210 * IrisStyle.density))
                    y: (gauges.height - height) / 2
                    label: Translation.tr("Download")
                    tint: IrisStyle.accent
                    value: root.downloadShare
                    figure: root.rateParts(root.downloadRate).value
                    unit: root.rateParts(root.downloadRate).unit
                }

                Column {
                    x: gauges.gaugeWidth + root.gap
                    width: gauges.infoWidth
                    height: implicitHeight
                    y: (gauges.height - height) / 2
                    spacing: Math.round(6 * IrisStyle.density)

                    Text {
                        text: Translation.tr("Latency")
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                    Text {
                        text: NetworkDetails.latencyMs >= 0 ? Math.round(NetworkDetails.latencyMs) + " ms" : "-"
                        color: IrisStyle.text
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: IrisStyle.typeLabel
                    }
                    Text {
                        text: Translation.tr("Loss")
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                    Text {
                        text: NetworkDetails.lossPercent >= 0 ? NetworkDetails.lossPercent.toFixed(1) + " %" : "-"
                        color: IrisStyle.text
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: IrisStyle.typeLabel
                    }
                    Item { width: 1; height: Math.max(4, parent.height * 0.06) }
                    Text {
                        text: Translation.tr("This session")
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontMain
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                    Text {
                        text: "↓ " + root.trafficText(NetworkDetails.rxBytes)
                            + "   ↑ " + root.trafficText(NetworkDetails.txBytes)
                        color: IrisStyle.text
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                }

                RadialGauge {
                    x: gauges.gaugeWidth + root.gap + gauges.infoWidth + root.gap
                    width: gauges.gaugeWidth
                    height: Math.min(gauges.height, Math.round(210 * IrisStyle.density))
                    y: (gauges.height - height) / 2
                    label: Translation.tr("Upload")
                    tint: IrisStyle.secondaryAccent
                    value: root.uploadShare
                    figure: root.rateParts(root.uploadRate).value
                    unit: root.rateParts(root.uploadRate).unit
                }
            }
        }
    }

    Rectangle {
        id: weatherCard
        anchors.left: networkCard.right
        anchors.leftMargin: root.gap
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.topMargin: root.gap
        anchors.bottom: parent.bottom
        radius: root.cardRadius
        color: IrisStyle.fill
        border.width: 1
        border.color: IrisStyle.hairline
        antialiasing: true

        Item {
            anchors.fill: parent
            anchors.margins: Math.round(18 * IrisStyle.density)

            Text {
                id: cityLabel
                width: parent.width
                text: Weather.visibleCity.length > 0 ? Weather.visibleCity : Translation.tr("Weather")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeLabel
                elide: Text.ElideRight
            }

            Text {
                visible: !root.weatherReady
                anchors.centerIn: parent
                text: Translation.tr("No weather data")
                color: IrisStyle.subtext
                font.family: IrisStyle.fontMain
                font.pixelSize: IrisStyle.typeBody
            }

            Row {
                id: currentRow
                visible: root.weatherReady
                width: parent.width
                anchors.top: cityLabel.bottom
                anchors.topMargin: Math.round(2 * IrisStyle.density)
                spacing: Math.round(14 * IrisStyle.density)

                Text {
                    id: currentTemp
                    text: root.tempLabel(Weather.data?.temp ?? "")
                    color: IrisStyle.text
                    font.family: IrisStyle.fontNumbers
                    font.pixelSize: Math.round(56 * IrisStyle.density)
                    font.weight: Font.DemiBold
                }
                Column {
                    anchors.bottom: currentTemp.bottom
                    anchors.bottomMargin: Math.round(6 * IrisStyle.density)
                    spacing: Math.round(2 * IrisStyle.density)

                    Row {
                        spacing: Math.round(6 * IrisStyle.density)
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.getWeatherIcon(Weather.data?.wCode ?? "", Weather.isNightNow()) ?? "cloud"
                            iconSize: Math.round(22 * IrisStyle.density)
                            color: IrisStyle.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.data?.description ?? ""
                            color: IrisStyle.text
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeLabel
                        }
                    }
                    Text {
                        text: "H:" + root.tempLabel(Weather.data?.tempMax ?? "")
                            + "  L:" + root.tempLabel(Weather.data?.tempMin ?? "")
                        color: IrisStyle.subtext
                        font.family: IrisStyle.fontNumbers
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                }
            }

            Row {
                id: hourlyRow
                visible: root.weatherReady
                width: parent.width
                height: Math.round(58 * IrisStyle.density)
                anchors.top: currentRow.bottom
                anchors.topMargin: Math.round(10 * IrisStyle.density)

                Repeater {
                    model: root.hourlySlots

                    Item {
                        required property var modelData
                        required property int index
                        width: hourlyRow.width / Math.max(1, root.hourlySlots.length)
                        height: hourlyRow.height

                        Column {
                            anchors.centerIn: parent
                            spacing: Math.round(3 * IrisStyle.density)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: index === 0 ? Translation.tr("Now") : modelData.label
                                color: IrisStyle.subtext
                                font.family: IrisStyle.fontNumbers
                                font.pixelSize: IrisStyle.typeCaption
                            }
                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Icons.getWeatherIcon(modelData.code, modelData.isNight) ?? "cloud"
                                iconSize: Math.round(18 * IrisStyle.density)
                                color: IrisStyle.text
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.temp
                                color: IrisStyle.text
                                font.family: IrisStyle.fontNumbers
                                font.pixelSize: IrisStyle.typeFootnote
                            }
                        }
                    }
                }
            }

            Column {
                id: dailyColumn
                visible: root.weatherReady
                anchors.top: hourlyRow.bottom
                anchors.topMargin: Math.round(8 * IrisStyle.density)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Repeater {
                    model: root.forecastDays

                    Item {
                        required property var modelData
                        width: dailyColumn.width
                        height: dailyColumn.height / Math.max(1, root.forecastDays.length)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(52 * IrisStyle.density)
                            text: modelData.dayName
                            color: IrisStyle.text
                            font.family: IrisStyle.fontMain
                            font.pixelSize: IrisStyle.typeFootnote
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.round(56 * IrisStyle.density)
                            text: Icons.getWeatherIcon(modelData.code, false) ?? "cloud"
                            iconSize: Math.round(17 * IrisStyle.density)
                            color: IrisStyle.subtext
                        }
                        Text {
                            id: lowText
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.round(84 * IrisStyle.density)
                            width: Math.round(34 * IrisStyle.density)
                            horizontalAlignment: Text.AlignRight
                            text: root.tempLabel(modelData.lo)
                            color: IrisStyle.subtext
                            font.family: IrisStyle.fontNumbers
                            font.pixelSize: IrisStyle.typeCaption
                        }
                        Item {
                            id: tempTrack
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: lowText.right
                            anchors.leftMargin: Math.round(8 * IrisStyle.density)
                            anchors.right: highText.left
                            anchors.rightMargin: Math.round(8 * IrisStyle.density)
                            height: Math.round(6 * IrisStyle.density)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: IrisStyle.fillHover
                            }
                            Rectangle {
                                x: tempTrack.width * (Number(modelData.loVal) - root.tempLow) / root.tempSpan
                                width: Math.max(Math.round(4 * IrisStyle.density),
                                    tempTrack.width * (Number(modelData.hiVal) - Number(modelData.loVal)) / root.tempSpan)
                                height: parent.height
                                radius: parent.height / 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: IrisStyle.accent }
                                    GradientStop { position: 1; color: IrisStyle.secondaryAccent }
                                }
                            }
                        }
                        Text {
                            id: highText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            width: Math.round(34 * IrisStyle.density)
                            horizontalAlignment: Text.AlignRight
                            text: root.tempLabel(modelData.hi)
                            color: IrisStyle.text
                            font.family: IrisStyle.fontNumbers
                            font.pixelSize: IrisStyle.typeCaption
                        }
                    }
                }
            }
        }
    }
}
