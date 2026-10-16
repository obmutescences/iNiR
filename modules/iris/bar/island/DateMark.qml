pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.iris.style
import qs.modules.iris.components

// The date beside the time: the Gregorian day, the Chinese calendar day, and the weekday in
// Chinese. The date and the lunar day hold the first colour, the weekday reads in the second,
// so the row's own detail stands out of it. The lunar name and the weekday come from Lunar, so
// the row reads the same on every layout instead of following the interface language, which
// would leave 初七 next to "Fri".
Row {
    id: dateMark
    property real pixelSize: IrisStyle.typeMeta
    property color dayColor: IrisStyle.secondaryAccent
    property color weekdayColor: IrisStyle.secondaryAccent
    readonly property var date: DateTime.clock.date
    readonly property string lunar: Lunar.dayName(dateMark.date)
    spacing: Math.round(dateMark.pixelSize * 0.3)
    IrisText {
        id: gregorianText
        text: Qt.locale().toString(dateMark.date, "MM-dd")
        color: dateMark.dayColor
        font.pixelSize: dateMark.pixelSize * 0.92
        font.family: IrisStyle.fontNumbers
        font.weight: IrisStyle.weight(Font.Medium)
        font.features: ({ "tnum": 1 })
    }
    IrisText {
        visible: dateMark.lunar.length > 0
        anchors.baseline: gregorianText.baseline
        text: dateMark.lunar
        color: dateMark.dayColor
        font.pixelSize: dateMark.pixelSize
        font.weight: IrisStyle.weight(Font.Bold)
    }
    IrisText {
        anchors.baseline: gregorianText.baseline
        text: Lunar.weekdayName(dateMark.date)
        color: dateMark.weekdayColor
        font.pixelSize: dateMark.pixelSize * 0.92
        font.weight: IrisStyle.weight(Font.Medium)
    }
}
