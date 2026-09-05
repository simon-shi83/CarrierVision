import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    property string startDate: ""
    property string endDate: ""
    property int wheelNumber: 1
    property string resultType: "NG"
    property var rackRows: []
    property int selectedRack: 0

    function normalizedResult() {
        return resultType.toUpperCase() === "OK" ? "OK" : "NG"
    }

    function loadStatistics() {
        if (!appController || !appController.wheelRackResultStats || wheelNumber <= 0)
            return

        var rows = appController.wheelRackResultStats(startDate, endDate,
                                                      wheelNumber, normalizedResult()) || []
        var filtered = []
        for (var i = 0; i < rows.length; ++i) {
            if (Number(rows[i].count) > 0)
                filtered.push(rows[i])
        }
        rackRows = filtered
        selectedRack = filtered.length > 0 ? Number(filtered[0].rack) : 0
        loadSelectedImages()
    }

    function loadSelectedImages() {
        if (selectedRack <= 0 || !appController || !appController.searchPaged)
            return
        appController.searchPaged(startDate, endDate, "", selectedRack,
                                  String(wheelNumber),
                                  normalizedResult() === "OK" ? "1" : "0",
                                  1, 1000)
    }

    onStartDateChanged: loadStatistics()
    onEndDateChanged: loadStatistics()
    onWheelNumberChanged: loadStatistics()
    onResultTypeChanged: loadStatistics()
    Component.onCompleted: loadStatistics()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.bgCard
        border.width: 1
        border.color: Theme.borderMedium

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // 顶栏汇总指示
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Theme.radiusMd
                color: Theme.bgCardElevated
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    Label {
                        text: "架轮判定下钻明细"
                        color: Theme.primaryLight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeH3
                        font.bold: true
                    }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.divider }
                    Label { text: "时间: " + (startDate || "--") + " ~ " + (endDate || "--"); color: Theme.textSecondary; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeSmall }
                    Label { text: "轮号: #" + wheelNumber; color: Theme.textPrimary; font.bold: true; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeSmall }
                    Label {
                        text: "判定: " + normalizedResult()
                        color: normalizedResult() === "OK" ? Theme.ok : Theme.ng
                        font.bold: true
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: "共 " + rackRows.length + " 个架号有记录"; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            // 下方：左列表 + 右缩略图
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // 左侧：架号清单
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            color: Theme.bgCardActive
                            radius: Theme.radiusSm

                            RowLayout {
                                anchors.fill: parent
                                Text { text: "架号"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                Text { text: "轮号"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                Text { text: "判定"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                Text { text: "计数"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                            }
                        }

                        ListView {
                            id: rackList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            model: root.rackRows

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: Number(modelData.rack) === root.selectedRack
                                width: rackList.width
                                height: 38
                                radius: Theme.radiusSm
                                color: selected ? Theme.bgCardActive : (itemMouse.containsMouse ? Theme.bgCardElevated : "transparent")
                                border.width: 1
                                border.color: selected ? Theme.primary : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    Text { text: "#" + parent.parent.modelData.rack; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: parent.parent.selected ? Theme.primaryLight : Theme.textPrimary; font.bold: true; font.family: Theme.fontMono }
                                    Text { text: String(root.wheelNumber); Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontMono }
                                    Text { text: root.normalizedResult(); Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: root.normalizedResult() === "OK" ? Theme.ok : Theme.ng; font.bold: true; font.family: Theme.fontMono }
                                    Text { text: parent.parent.modelData.count; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: Theme.textPrimary; font.bold: true; font.family: Theme.fontMono }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedRack = Number(parent.modelData.rack)
                                        root.loadSelectedImages()
                                    }
                                }
                            }
                        }
                    }
                }

                // 右侧：检测缩略图网格
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: selectedRack > 0 ? "架号 #" + selectedRack + " 的检测原图" : "检测原图"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeH3
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "共 " + (appController.searchImagesModel ? appController.searchImagesModel.count : 0) + " 张图像"
                                color: Theme.textSecondary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        GridView {
                            id: thumbnailView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            cellWidth: 220
                            cellHeight: 180
                            model: appController ? appController.searchImagesModel : null

                            delegate: Rectangle {
                                width: 210
                                height: 170
                                radius: Theme.radiusMd
                                color: thumbMouse.containsMouse ? Theme.bgCardActive : Theme.bgCard
                                border.width: 1
                                border.color: thumbMouse.containsMouse ? Theme.primary : Theme.borderSubtle

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Theme.radiusSm
                                        color: Theme.bgInput
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: fileUrl || ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            cache: false
                                            smooth: true
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: fileName
                                        color: Theme.textPrimary
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeTiny
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: receivedAtText
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeTiny
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: thumbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onDoubleClicked: {
                                        inspectViewer.openViewer(fileUrl, fileName, "架 #" + rack + " ╎ 轮 #" + slot + " ╎ " + receivedAtText)
                                    }
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: thumbnailView.count === 0
                                text: selectedRack > 0 ? "暂无图片" : "请从左侧选择架号"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }
        }
    }

    ZoomOverlay {
        id: inspectViewer
        anchors.fill: parent
    }
}
