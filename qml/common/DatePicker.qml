import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ============ 红点奖标准 工业高精日历选择器 (Red Dot Precision Calendar) ============
Rectangle {
    id: root
    width: parent ? parent.width : 140
    height: parent ? parent.height : 34
    color: Theme.fieldFill
    radius: Theme.radiusSmall
    border.color: calendarPopup.visible ? Theme.selectedBorder : (inputMouse.containsMouse ? Theme.borderStrong : Theme.border)
    border.width: 1

    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    // ============ 对外属性 ============
    property date selectedDate: new Date()
    property string dateString: formatDate(selectedDate)
    property string labelText: ""

    // ============ 信号 ============
    signal dateChanged(date date)

    // ============ 内部状态 ============
    property int viewYear: selectedDate.getFullYear()
    property int viewMonth: selectedDate.getMonth() // 0 ~ 11

    onSelectedDateChanged: {
        var canonical = formatDate(selectedDate)
        if (canonical !== "" && dateString !== canonical)
            dateString = canonical
    }

    function formatDate(d) {
        if (!d || isNaN(d.getTime())) return ""
        var y = d.getFullYear()
        var m = String(d.getMonth() + 1).padStart(2, '0')
        var day = String(d.getDate()).padStart(2, '0')
        return y + "-" + m + "-" + day
    }

    function parseDate(str) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(str || "")) return null
        var parts = str.split("-")
        var y = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10) - 1
        var d = parseInt(parts[2], 10)
        if (y < 100 || m < 0 || m > 11 || d < 1 || d > 31) return null
        var parsed = new Date(0)
        parsed.setHours(0, 0, 0, 0)
        parsed.setFullYear(y, m, d)
        if (parsed.getFullYear() !== y || parsed.getMonth() !== m || parsed.getDate() !== d)
            return null
        return parsed
    }

    onDateStringChanged: {
        var parsed = parseDate(dateString)
        if (parsed && formatDate(parsed) !== formatDate(selectedDate)) {
            selectedDate = parsed
            viewYear = parsed.getFullYear()
            viewMonth = parsed.getMonth()
        }
    }

    function selectDate(d) {
        if (!d || isNaN(d.getTime())) return
        selectedDate = d
        viewYear = d.getFullYear()
        viewMonth = d.getMonth()
        dateChanged(selectedDate)
        calendarPopup.close()
    }

    function applyPreset(daysAgo) {
        var d = new Date()
        d.setDate(d.getDate() - daysAgo)
        selectDate(d)
    }

    function prevMonth() {
        if (viewMonth === 0) {
            viewYear--
            viewMonth = 11
        } else {
            viewMonth--
        }
    }

    function nextMonth() {
        if (viewMonth === 11) {
            viewYear++
            viewMonth = 0
        } else {
            viewMonth++
        }
    }

    // ============ 输入框条目展示 ============
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

        AppIcon {
            name: "icon_calendar"
            size: 14
            color: calendarPopup.visible ? Theme.accent : (inputMouse.containsMouse ? Theme.text : Theme.textSoft)
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: labelTextItem
            text: root.labelText
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontMedium
            color: Theme.textSoft
            visible: root.labelText !== ""
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: dateDisplayText
            text: root.dateString.length > 0 ? root.dateString : "选择日期"
            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontMedium
            color: root.dateString.length > 0 ? Theme.text : Theme.muted
            Layout.fillWidth: true
            horizontalAlignment: root.labelText === "" ? Text.AlignHCenter : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        AppIcon {
            Layout.alignment: Qt.AlignVCenter
            name: "icon_arrow_down"
            size: 12
            color: calendarPopup.visible ? Theme.accent : Theme.muted
        }
    }

    MouseArea {
        id: inputMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (calendarPopup.visible) {
                calendarPopup.close()
            } else {
                root.viewYear = root.selectedDate.getFullYear()
                root.viewMonth = root.selectedDate.getMonth()
                calendarPopup.open()
            }
        }
    }

    // ============ 现代整体日历弹出层 ============
    Popup {
        id: calendarPopup
        y: root.height + 4
        width: 296
        height: 350
        padding: 12
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        z: 999

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surfaceFloating
            border.width: 1
            border.color: Theme.border

            // 柔和投影层
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.selectedBorder
                opacity: 0.15
            }
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // 1. 快捷选择胶囊区 (Quick Presets)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: [
                        { label: "今天", days: 0 },
                        { label: "昨天", days: 1 },
                        { label: "前天", days: 2 },
                        { label: "7天前", days: 7 }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        radius: Theme.radiusMicro
                        color: presetMouse.containsMouse ? Theme.pressed : Theme.surfaceAlt
                        border.color: presetMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                            color: presetMouse.containsMouse ? Theme.text : Theme.textSoft
                        }

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyPreset(modelData.days)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderMuted
            }

            // 2. 年月导航栏
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: Theme.radiusMicro
                    color: prevMouse.containsMouse ? Theme.pressed : "transparent"

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_chevron_left"
                        size: 16
                        color: prevMouse.containsMouse ? Theme.text : Theme.textSoft
                    }

                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.prevMonth()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.viewYear + " 年 " + String(root.viewMonth + 1).padStart(2, '0') + " 月"
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.fontMedium
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: Theme.radiusMicro
                    color: nextMouse.containsMouse ? Theme.pressed : "transparent"

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_chevron_right"
                        size: 16
                        color: nextMouse.containsMouse ? Theme.text : Theme.textSoft
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextMonth()
                    }
                }
            }

            // 3. 星期表头
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: ["一", "二", "三", "四", "五", "六", "日"]
                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontMicro
                            font.weight: Theme.fontMedium
                            color: (index >= 5) ? Theme.textSoft : Theme.muted
                        }
                    }
                }
            }

            // 4. 42天网格面板 (6行 × 7列)
            GridLayout {
                id: daysGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 2
                columnSpacing: 2

                readonly property int firstDayWeekday: {
                    var day = new Date(root.viewYear, root.viewMonth, 1).getDay()
                    return day === 0 ? 6 : (day - 1)
                }
                readonly property int daysInCurrentMonth: new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
                readonly property int daysInPrevMonth: new Date(root.viewYear, root.viewMonth, 0).getDate()

                Repeater {
                    model: 42
                    delegate: Rectangle {
                        id: dayCell
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusMicro

                        readonly property int cellIndex: index
                        readonly property bool isPrevMonth: cellIndex < daysGrid.firstDayWeekday
                        readonly property bool isNextMonth: cellIndex >= (daysGrid.firstDayWeekday + daysGrid.daysInCurrentMonth)
                        readonly property bool isCurrentMonth: !isPrevMonth && !isNextMonth

                        readonly property int dayNumber: {
                            if (isPrevMonth) {
                                return daysGrid.daysInPrevMonth - daysGrid.firstDayWeekday + cellIndex + 1
                            } else if (isCurrentMonth) {
                                return cellIndex - daysGrid.firstDayWeekday + 1
                            } else {
                                return cellIndex - daysGrid.firstDayWeekday - daysGrid.daysInCurrentMonth + 1
                            }
                        }

                        readonly property date cellDate: {
                            if (isPrevMonth) {
                                return new Date(root.viewYear, root.viewMonth - 1, dayNumber)
                            } else if (isCurrentMonth) {
                                return new Date(root.viewYear, root.viewMonth, dayNumber)
                            } else {
                                return new Date(root.viewYear, root.viewMonth + 1, dayNumber)
                            }
                        }

                        readonly property bool isSelected: isCurrentMonth 
                            && root.formatDate(cellDate) === root.formatDate(root.selectedDate)

                        readonly property bool isToday: root.formatDate(cellDate) === root.formatDate(new Date())

                        color: isSelected 
                            ? Theme.accent 
                            : (dayMouse.containsMouse ? Theme.pressed : "transparent")

                        border.width: isToday && !isSelected ? 1 : 0
                        border.color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.dayNumber
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.pixelSize: Theme.fontCaption
                            font.weight: (dayCell.isSelected || dayCell.isToday) ? Theme.fontMedium : Theme.fontRegular
                            color: dayCell.isSelected 
                                ? Theme.textOnAccent 
                                : (!dayCell.isCurrentMonth ? Theme.disabled : Theme.text)
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectDate(dayCell.cellDate)
                            }
                        }
                    }
                }
            }
        }
    }
}
