import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    height: 52
    color: Theme.bgCard
    radius: Theme.radiusMd
    border.color: Theme.borderMedium
    border.width: 1

    // ===== 对外暴露的属性 =====
    property string keyword: ""
    property string startDate: startDateField.dateString
    property string endDate: endDateField.dateString
    property int rackno: rackField.selectedValue
    property string turno: wheelSelector.selectionToken
    property string result: includeResult ? resultCombo.currentText : "全部"
    property int imageCount: 0

    // ===== 对外暴露的配置属性 =====
    property string placeholderText: "轮次..."
    property string datePlaceholder: "YYYY-MM-DD"
    property var resultList: ["全部", "OK", "NG"]
    property bool includeResult: true

    // ===== 信号 =====
    signal searchClicked(string startDate, string endDate, int rackno, string turno, string result, string keyword)
    signal resetClicked()

    function clearAll() {
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
        startDateField.dateString = today
        endDateField.dateString = today
        rackField.selectedValue = 0
        wheelSelector.reset()
        resultCombo.currentIndex = 0
    }

    function applyQuery(start, end, wheel, resultType) {
        startDateField.dateString = start
        endDateField.dateString = end
        wheelSelector.setSelectionToken(wheel)
        var resultIndex = root.resultList.indexOf(resultType)
        resultCombo.currentIndex = resultIndex >= 0 ? resultIndex : 0
        root.searchClicked(startDateField.dateString, endDateField.dateString,
                           root.rackno, root.turno,
                           resultCombo.currentText, "")
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        // 日期范围
        RowLayout {
            spacing: 6
            Label {
                text: "日期范围"
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

        // 分隔竖线
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 22
            color: Theme.divider
            Layout.alignment: Qt.AlignVCenter
        }

        // 架号
        RowLayout {
            spacing: 6
            Label { 
                text: "架号" 
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary 
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter 
            }
            NumPicker {
                id: rackField
                selectedValue: 0
                Layout.preferredWidth: 76
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // 分隔竖线
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 22
            color: Theme.divider
            Layout.alignment: Qt.AlignVCenter
        }

        // 轮号
        RowLayout {
            spacing: 6
            Label { 
                text: "轮号" 
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary 
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter 
            }
            WheelSelector {
                id: wheelSelector
                Layout.preferredWidth: 130
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // 结果
        RowLayout {
            visible: root.includeResult
            spacing: 6
            Label {
                text: "判定"
                font.family: Theme.fontFamily
                font.bold: true
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter
            }
            ComboBox {
                id: resultCombo
                Layout.preferredWidth: 80
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                model: root.resultList
                currentIndex: 0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody

                background: Rectangle {
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.color: resultCombo.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                    border.width: 1
                }
                contentItem: Text {
                    text: resultCombo.currentText
                    color: resultCombo.currentText === "OK" ? Theme.ok : (resultCombo.currentText === "NG" ? Theme.ng : Theme.textPrimary)
                    font.bold: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                popup: Popup {
                    y: resultCombo.height + 4
                    width: resultCombo.width
                    implicitHeight: contentItem.implicitHeight + 8
                    padding: 4
                    background: Rectangle {
                        color: Theme.bgPopup
                        radius: Theme.radiusMd
                        border.color: Theme.borderMedium
                        border.width: 1
                    }
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: resultCombo.popup.visible ? resultCombo.delegateModel : null
                        currentIndex: resultCombo.highlightedIndex
                    }
                }
                delegate: ItemDelegate {
                    width: resultCombo.width - 8
                    height: 30
                    contentItem: Text {
                        text: modelData
                        color: modelData === "OK" ? Theme.ok : (modelData === "NG" ? Theme.ng : Theme.textPrimary)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: highlighted ? Theme.bgCardActive : "transparent"
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // 查询按钮
        ActionButton {
            id: searchBtn
            text: "查询"
            variant: "primary"
            Layout.preferredWidth: 80
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            onClicked: {
                root.searchClicked(startDateField.dateString, endDateField.dateString,
                                   root.rackno, root.turno, root.result, "")
            }
        }

        // 清空按钮
        ActionButton {
            id: resetBtn
            text: "重置"
            variant: "secondary"
            Layout.preferredWidth: 80
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            onClicked: { root.clearAll(); root.resetClicked(); }
        }
    }

    Component.onCompleted: {
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
        startDateField.dateString = today
        endDateField.dateString = today
    }
}
