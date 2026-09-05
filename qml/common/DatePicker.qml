import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ============ 红点奖标准 工业高精日历选择器 (Red Dot Precision Calendar) ============
Rectangle {
    id: root
    width: parent ? parent.width : 140
    height: parent ? parent.height : 34
    color: Theme.bgInput
    radius: Theme.radiusMd
    border.color: calendarPopup.visible ? Theme.borderHighlight : (inputMouse.containsMouse ? Theme.borderHover : Theme.borderMedium)
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
            color: calendarPopup.visible ? Theme.primaryLight : (inputMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary)
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: labelTextItem
            text: root.labelText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            color: Theme.textSecondary
            visible: root.labelText !== ""
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            id: dateDisplayText
            text: root.dateString.length > 0 ? root.dateString : "选择日期"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: root.dateString.length > 0 ? Theme.textPrimary : Theme.textMuted
            Layout.fillWidth: true
            horizontalAlignment: root.labelText === "" ? Text.AlignHCenter : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            text: "▾"
            font.pixelSize: 10
            color: calendarPopup.visible ? Theme.primaryLight : Theme.textMuted
            Layout.alignment: Qt.AlignVCenter
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
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium

            // 柔和投影层
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.borderHighlight
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
                        radius: Theme.radiusSm
                        color: presetMouse.containsMouse ? Theme.bgCardActive : Theme.bgCardElevated
                        border.color: presetMouse.containsMouse ? Theme.borderHover : Theme.borderSubtle
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: presetMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
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
                color: Theme.divider
            }

            // 2. 年月导航栏
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: Theme.radiusSm
                    color: prevMouse.containsMouse ? Theme.bgCardActive : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        font.pixelSize: 18
                        font.bold: true
                        color: prevMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeH3
                    font.bold: true
                    color: Theme.textPrimary
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: Theme.radiusSm
                    color: nextMouse.containsMouse ? Theme.bgCardActive : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        font.pixelSize: 18
                        font.bold: true
                        color: nextMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
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
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeTiny
                            font.bold: true
                            color: (index >= 5) ? Theme.walkWheel : Theme.textMuted
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
                        radius: Theme.radiusSm

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
                            ? Theme.primary 
                            : (dayMouse.containsMouse ? Theme.bgCardActive : "transparent")

                        border.width: isToday && !isSelected ? 1 : 0
                        border.color: Theme.primaryLight

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.dayNumber
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: dayCell.isSelected || dayCell.isToday
                            color: dayCell.isSelected 
                                ? "#ffffff" 
                                : (!dayCell.isCurrentMonth ? Theme.textDisabled : Theme.textPrimary)
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
