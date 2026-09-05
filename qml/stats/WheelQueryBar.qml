import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Rectangle {
    id: root
    height: 56
    color: Theme.bgCard
    radius: Theme.radiusMd
    border.color: Theme.borderMedium
    border.width: 1

    // 对外属性
    property bool isWalkWheel: false
    readonly property int wheelOffset: isWalkWheel ? 11 : 1
    readonly property color wheelColor: isWalkWheel ? Theme.walkWheel : Theme.driveWheel
    readonly property string wheelLabel: isWalkWheel ? "走行轮" : "驱动轮"

    property string startDate: startDateField.dateString
    property string endDate: endDateField.dateString
    property string rackno: rackField.selectedValue
    property var selectedTurns: isWalkWheel ? [11, 12, 13, 14, 15, 16, 17, 18] : [1, 2, 3, 4, 5, 6, 7, 8]

    // 信号
    signal searchClicked(string startDate, string endDate, string rackno, var selectedTurns)
    signal resetClicked()

    function generateCsv() {
        var arr = appController.gearSumResult
        if (!arr || arr.length === 0) return ""
        var csv = "轮号,ok数,ng数\n"
        for (var i = 0; i < arr.length; i++) {
            var r = arr[i]
            var wheel = (r.wheel !== undefined) ? r.wheel : (i + root.wheelOffset)
            var ok = (r.ok !== undefined) ? r.ok : 0
            var ng = (r.ng !== undefined) ? r.ng : 0
            csv += String(wheel) + "," + String(ok) + "," + String(ng) + "\n"
        }
        return csv
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        // 日期
        RowLayout {
            spacing: 6
            Label {
                text: "日期"
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            DatePicker {
                id: startDateField
                Layout.preferredWidth: 136
                Layout.preferredHeight: 34
            }
            Label { text: "~"; color: Theme.textMuted; font.bold: true }
            DatePicker {
                id: endDateField
                Layout.preferredWidth: 136
                Layout.preferredHeight: 34
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 22; color: Theme.divider }

        // 架号
        RowLayout {
            spacing: 6
            Label {
                text: "架号"
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            NumPicker {
                id: rackField
                selectedValue: 0
                Layout.preferredWidth: 76
                Layout.preferredHeight: 34
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 22; color: Theme.divider }

        // 轮号多选
        RowLayout {
            spacing: 6
            Label {
                text: root.wheelLabel
                font.family: Theme.fontFamily
                font.bold: true
                color: root.wheelColor
                font.pixelSize: Theme.fontSizeSmall
            }
            RowLayout {
                spacing: 3
                Repeater {
                    id: turnRepeater
                    model: 8
                    delegate: Button {
                        required property int index
                        property int wheelNumber: index + root.wheelOffset
                        text: String(wheelNumber)
                        checkable: true
                        checked: root.selectedTurns.indexOf(wheelNumber) !== -1
                        Layout.preferredWidth: root.isWalkWheel ? 28 : 26
                        Layout.preferredHeight: 28
                        onClicked: {
                            var found = root.selectedTurns.indexOf(wheelNumber)
                            var turns = root.selectedTurns.slice()
                            if (found === -1) turns.push(wheelNumber)
                            else turns.splice(found, 1)
                            turns.sort(function(a, b) { return a - b })
                            root.selectedTurns = turns
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.checked ? "#ffffff" : Theme.textSecondary
                            font.family: Theme.fontMono
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: parent.checked ? root.wheelColor : (parent.hovered ? Theme.bgCardActive : Theme.bgInput)
                            border.width: 1
                            border.color: parent.checked ? root.wheelColor : Theme.borderSubtle
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // 操作按钮
        ActionButton {
            id: searchBtn
            text: "开始统计"
            variant: "primary"
            Layout.preferredWidth: 90
            Layout.preferredHeight: 34
            onClicked: {
                root.searchClicked(startDateField.dateString, endDateField.dateString, root.rackno, root.selectedTurns)
            }
        }

        ActionButton {
            id: resetBtn
            text: "重置"
            variant: "secondary"
            Layout.preferredWidth: 70
            Layout.preferredHeight: 34
            onClicked: {
                var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
                startDateField.dateString = today
                endDateField.dateString = today
                rackField.selectedValue = 0
                root.selectedTurns = root.isWalkWheel ? [11, 12, 13, 14, 15, 16, 17, 18] : [1, 2, 3, 4, 5, 6, 7, 8]
                root.resetClicked()
            }
        }

        ActionButton {
            id: exportBtnToolbar
            text: "导出 CSV"
            variant: "secondary"
            Layout.preferredWidth: 90
            Layout.preferredHeight: 34
            onClicked: {
                saveDialog.open()
            }
        }

        Dialog {
            id: saveDialog
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 440
            modal: true
            title: "导出" + root.wheelLabel + "统计为 CSV"
            standardButtons: Dialog.Ok | Dialog.Cancel

            background: Rectangle {
                radius: Theme.radiusLg
                color: Theme.bgPopup
                border.color: Theme.borderMedium
                border.width: 1
            }

            onVisibleChanged: {
                if (visible) {
                    var rack = rackField.selectedValue
                    var rackLabel = (rack === 0) ? "All" : rack
                    var dateStr = Qt.formatDate(new Date(), "yyyyMMdd")
                    if (startDateField && startDateField.dateString) {
                        var s = startDateField.dateString
                        if (s && s.length >= 10) dateStr = s.replace(/-/g, '').substr(0, 8)
                    }
                    fileNameInput.text = root.wheelLabel + "_架" + (rackLabel ? rackLabel : "") + "_" + dateStr + "统计表.csv"
                }
            }
            onAccepted: {
                var name = fileNameInput.text.trim()
                if (name.length === 0) {
                    fileNameInput.forceActiveFocus()
                    return
                }
                if (!name.endsWith('.csv')) name += '.csv'
                var filename = "data/" + name
                var csv = generateCsv()
                appController.saveCsv(filename, csv)
                saveDialog.close()
            }

            contentItem: ColumnLayout {
                spacing: 10
                Label {
                    text: "将保存到应用数据目录 (data/)"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
                RowLayout {
                    spacing: 8
                    Label { text: "文件名:"; color: Theme.textPrimary; font.bold: true }
                    TextField {
                        id: fileNameInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        background: Rectangle {
                            radius: Theme.radiusMd
                            color: Theme.bgInput
                            border.color: fileNameInput.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
        startDateField.dateString = today
        endDateField.dateString = today
        rackField.selectedValue = 0
    }
}