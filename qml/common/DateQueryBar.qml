import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

Rectangle {
    id: root
    height: 52
    color: Theme.bgCard
    radius: Theme.radiusMd
    border.color: Theme.borderMedium
    border.width: 1

    // 对外属性
    property string startDate: startDateField.dateString
    property string endDate: endDateField.dateString
    // 查询类型 0:驱动轮 / 1:走行轮
    property int wheelType: 0
    property alias sheeltype: root.wheelType // 兼容历史别名
    property string exportCsvContent: ""

    // 信号
    signal searchClicked(string startDate, string endDate)
    signal resetClicked

    function generateCsv() {
        if (exportCsvContent.length > 0)
            return exportCsvContent;
        if (typeof appController === 'undefined' || !appController || !appController.gearSumResult)
            return "";
        var arr = appController.gearSumResult;
        if (!arr || arr.length === 0)
            return "";
        var csv = "轮号,ok数,ng数\n";
        for (var i = 0; i < arr.length; i++) {
            var r = arr[i];
            var wheel = (r.wheel !== undefined) ? r.wheel : (i + 1);
            var ok = (r.ok !== undefined) ? r.ok : 0;
            var ng = (r.ng !== undefined) ? r.ng : 0;
            csv += String(wheel) + "," + String(ok) + "," + String(ng) + "\n";
        }
        return csv;
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        RowLayout {
            spacing: 6
            Label {
                text: "统计区间"
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter
            }
            DatePicker {
                id: startDateField
                Layout.preferredWidth: 136
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
            }
            Label {
                text: "~"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
            DatePicker {
                id: endDateField
                Layout.preferredWidth: 136
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // 操作按钮
        ActionButton {
            id: searchBtn
            text: "开始统计"
            variant: "primary"
            Layout.preferredWidth: 90
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            onClicked: {
                root.searchClicked(startDateField.dateString, endDateField.dateString);
            }
        }

        ActionButton {
            id: resetBtn
            text: "重置"
            variant: "secondary"
            Layout.preferredWidth: 70
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            onClicked: {
                var today = Qt.formatDate(new Date(), "yyyy-MM-dd");
                startDateField.dateString = today;
                endDateField.dateString = today;
                root.resetClicked();
            }
        }

        ActionButton {
            id: exportBtnToolbar
            text: "导出报表"
            variant: "secondary"
            Layout.preferredWidth: 90
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            onClicked: {
                saveDialog.open();
            }
        }

        Dialog {
            id: saveDialog
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 440
            modal: true
            title: "导出 CSV 报表"
            standardButtons: Dialog.Ok | Dialog.Cancel

            background: Rectangle {
                radius: Theme.radiusLg
                color: Theme.bgPopup
                border.color: Theme.borderMedium
                border.width: 1
            }

            onVisibleChanged: {
                if (visible) {
                    var startText = root.startDate ? root.startDate.replace(/-/g, "") : "";
                    var endText = root.endDate ? root.endDate.replace(/-/g, "") : "";
                    var typeText = root.wheelType === 1 ? "走行轮" : "驱动轮";
                    fileNameInput.text = typeText + "_" + startText + "_" + endText + ".csv";
                }
            }
            onAccepted: {
                var name = fileNameInput.text.trim();
                if (name.length === 0) {
                    fileNameInput.forceActiveFocus();
                    return;
                }
                if (!name.endsWith('.csv'))
                    name += '.csv';
                var filename = "data/" + name;
                var csv = generateCsv();
                if (appController.saveCsv(filename, csv)) {
                    saveDialog.close();
                }
            }

            contentItem: ColumnLayout {
                spacing: 10
                Label {
                    text: "报表将保存至应用数据目录 (data/)"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
                RowLayout {
                    spacing: 8
                    Label {
                        text: "文件名:"
                        color: Theme.textPrimary
                        font.bold: true
                    }
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
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        startDateField.dateString = today;
        endDateField.dateString = today;
    }
}
