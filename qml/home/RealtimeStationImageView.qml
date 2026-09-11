import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Rectangle {
    id: root
    anchors.fill: parent

    Layout.fillWidth: true
    Layout.fillHeight: true

    property var imageModel: (typeof appController !== 'undefined' && appController) ? appController.currentImagesModel : null
    property string titleText: "实时工位图像监控"
    property string summaryText: (appController && appController.currentSerialsRaw && appController.currentSerialsRaw.length > 0)
                                     ? ("当前序列号: " + appController.currentSerialsRaw)
                                     : "等待点检数据..."
    property string emptyText: "等待新的批次图像到达"

    function refreshSlot(slot) {
        if (slot >= 0 && slot < cardRepeater.count) {
            var item = cardRepeater.itemAt(slot)
            if (item && item.syncFromModel) {
                item.syncFromModel()
            }
        }
    }

    function refreshAllSlots() {
        for (var i = 0; i < cardRepeater.count; ++i) {
            var item = cardRepeater.itemAt(i)
            if (item && item.syncFromModel) {
                item.syncFromModel()
            }
        }
    }

    Connections {
        target: typeof appController !== 'undefined' ? appController : null
        function onSlotUpdated(slot) {
            root.refreshSlot(slot)
        }
    }

    Connections {
        target: root.imageModel && root.imageModel.dataChanged ? root.imageModel : null
        ignoreUnknownSignals: true
        function onDataChanged(topLeft, bottomRight) {
            var start = (topLeft && typeof topLeft.row !== 'undefined') ? topLeft.row : 0
            var end = (bottomRight && typeof bottomRight.row !== 'undefined') ? bottomRight.row : (cardRepeater.count - 1)
            for (var r = start; r <= end; ++r) {
                root.refreshSlot(r)
            }
        }
        function onModelReset() {
            root.refreshAllSlots()
        }
    }

    onImageModelChanged: {
        root.refreshAllSlots()
    }

    property bool embeddedMode: false
    property var externalViewer: null

    radius: embeddedMode ? 0 : Theme.radiusLg
    color: embeddedMode ? "transparent" : Theme.bgCard
    border.width: embeddedMode ? 0 : 1
    border.color: embeddedMode ? "transparent" : Theme.borderMedium

    StationImageInspectDialog {
        id: stationInspectDialog
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.embeddedMode ? 0 : 12
        spacing: root.embeddedMode ? 0 : 8

        // 顶栏汇总指示
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.embeddedMode

            Rectangle {
                width: 4
                height: 18
                radius: 2
                color: Theme.primary
            }

            Label {
                text: root.titleText
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeH2
                font.bold: true
            }

            Rectangle {
                Layout.preferredHeight: 22
                implicitWidth: serialMsgText.implicitWidth + 16
                radius: Theme.radiusPill
                color: Theme.bgCardElevated
                border.color: Theme.borderSubtle
                border.width: 1
                visible: root.summaryText.length > 0

                Text {
                    id: serialMsgText
                    anchors.centerIn: parent
                    text: root.summaryText
                    color: Theme.primaryLight
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredHeight: 22
                implicitWidth: hintRow.implicitWidth + 14
                radius: Theme.radiusPill
                color: Theme.bgCardElevated
                border.color: Theme.borderSubtle
                border.width: 1

                RowLayout {
                    id: hintRow
                    anchors.centerIn: parent
                    spacing: 4

                    AppIcon {
                        name: "icon_eye"
                        size: 11
                        color: Theme.textMuted
                    }

                    Text {
                        text: "轻触或双击卡片进入全景缩放"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeTiny
                    }
                }
            }
        }

        // 8/12 相机网格容器
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMd
            color: Theme.bgInput
            border.width: 1
            border.color: Theme.borderSubtle

            GridLayout {
                id: gridLayout
                anchors.fill: parent
                anchors.margins: 8
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    id: cardRepeater
                    model: (root.imageModel && root.imageModel.count > 0) ? root.imageModel.count : 12
                    RealtimeStationImageCard {
                        slotIndex: index
                        imageModel: root.imageModel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onActivate: function(sourceUrl, title, subtitle, slot) {
                            var sIdx = (typeof slot !== 'undefined') ? slot : index
                            stationInspectDialog.openViewer(sourceUrl, title, subtitle, sIdx, root.imageModel)
                        }
                    }
                }
            }
        }
    }
}
