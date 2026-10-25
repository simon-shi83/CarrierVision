import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    property string startDate: ""
    property string endDate: ""
    property int rackNumber: 1
    property string resultType: "NG"
    property int wheelType: 0
    property var wheelRows: []
    property int selectedWheel: 0

    readonly property int firstWheel: wheelType === 1 ? 1 : 9
    readonly property string wheelTypeName: wheelType === 1 ? "走行轮" : "驱动轮"

    function normalizedResult() {
        return resultType.toUpperCase() === "OK" ? "OK" : "NG"
    }

    function displayWheel(wheel) {
        return appController.wheelLabel(wheel);
    }

    property int statsRequestId: -1
    // 图像总数（后端单次最多返回 200 张，超出时界面注明只显示最新部分）
    property int imageTotal: 0

    function loadStatistics() {
        if (!appController || !appController.requestStats || rackNumber <= 0)
            return
        statsRequestId = appController.requestStats("rackWheelResultStats",
            [startDate, endDate, rackNumber, normalizedResult(), wheelType])
    }

    function applyStatistics(rows) {
        wheelRows = rows
        selectedWheel = wheelRows.length > 0 ? Number(wheelRows[0].wheel) : 0
        loadSelectedImages()
    }

    function loadSelectedImages() {
        if (selectedWheel <= 0 || !appController || !appController.searchPaged)
            return
        appController.searchPaged(startDate, endDate, "", rackNumber, String(selectedWheel),
                                  normalizedResult() === "OK" ? "1" : "0", 1, 200)
    }

    onStartDateChanged: loadStatistics()
    onEndDateChanged: loadStatistics()
    onRackNumberChanged: loadStatistics()
    onResultTypeChanged: loadStatistics()
    onWheelTypeChanged: loadStatistics()
    Component.onCompleted: loadStatistics()

    Connections {
        target: appController
        function onStatsReady(requestId, kind, result) {
            if (requestId === root.statsRequestId)
                root.applyStatistics(result || [])
        }
        function onSearchPagedResult(totalCount) {
            root.imageTotal = totalCount
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Theme.radiusSmall
                color: Theme.surfaceAlt
                border.width: 1
                border.color: Theme.borderMuted

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    Label {
                        text: wheelTypeName + " 判定下钻明细"
                        color: wheelType === 1 ? Theme.walkWheel : Theme.driveWheel
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.fontMedium
                    }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.borderMuted }
                    Label { text: "时间: " + (startDate || "--") + " ~ " + (endDate || "--"); color: Theme.textSoft; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular; font.pixelSize: Theme.fontCaption }
                    Label { text: "架号: #" + rackNumber; color: Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular; font.pixelSize: Theme.fontCaption }
                    Label {
                        text: "判定: " + normalizedResult()
                        color: normalizedResult() === "OK" ? Theme.ok : Theme.danger
                        font.weight: Theme.fontMedium
                        font.pixelSize: Theme.fontCaption
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: wheelTypeName + (wheelType === 1 ? "（轮位1～8）" : "（轮位9～16）"); color: Theme.muted; font.pixelSize: Theme.fontCaption }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // 左侧：轮位清单
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.fieldFill
                    border.width: 1
                    border.color: Theme.borderMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            color: Theme.pressed
                            radius: Theme.radiusMicro

                            RowLayout {
                                anchors.fill: parent
                                Text { text: "架号"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                                Text { text: "轮位"; Layout.preferredWidth: 136; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                                Text { text: "判定"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                                Text { text: "计数"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                            }
                        }

                        ListView {
                            id: wheelList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            model: root.wheelRows

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: Number(modelData.wheel) === root.selectedWheel
                                width: wheelList.width
                                height: 38
                                radius: Theme.radiusMicro
                                color: selected ? Theme.pressed : (wheelMouse.containsMouse ? Theme.surfaceAlt : "transparent")
                                border.width: 1
                                border.color: selected ? Theme.accent : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    Text { text: "#" + parent.parent.modelData.rack; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: Theme.textSoft; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: root.displayWheel(Number(parent.parent.modelData.wheel)); Layout.preferredWidth: 136; horizontalAlignment: Text.AlignHCenter; color: parent.parent.selected ? Theme.accent : Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: parent.parent.modelData.result; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: root.normalizedResult() === "OK" ? Theme.ok : Theme.danger; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: parent.parent.modelData.count; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                }

                                MouseArea {
                                    id: wheelMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedWheel = Number(parent.modelData.wheel)
                                        root.loadSelectedImages()
                                    }
                                }
                            }
                        }
                    }
                }

                // 右侧：原图网格
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.fieldFill
                    border.width: 1
                    border.color: Theme.borderMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: selectedWheel > 0 ? "架号 #" + rackNumber + " · " + displayWheel(selectedWheel) + " 的检测原图" : "检测原图"
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontMedium
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: {
                                    var shown = appController.searchImagesModel ? appController.searchImagesModel.count : 0
                                    return root.imageTotal > shown ? ("共 " + root.imageTotal + " 张，显示最新 " + shown + " 张")
                                                                   : ("共 " + shown + " 张图像")
                                }
                                color: Theme.textSoft
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
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
                                radius: Theme.radiusSmall
                                color: thumbMouse.containsMouse ? Theme.pressed : Theme.surface
                                border.width: 1
                                border.color: thumbMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Theme.radiusMicro
                                        color: Theme.fieldFill
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: fileUrl || ""
                                            // 按显示尺寸的 2 倍解码，避免按相机原图分辨率占用内存
                                            sourceSize.width: Math.min(4096, Math.max(1, width * 2))
                                            sourceSize.height: Math.min(4096, Math.max(1, height * 2))
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            cache: false
                                            smooth: true
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: fileName
                                        color: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontMicro
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: receivedAtText
                                        color: Theme.muted
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.pixelSize: Theme.fontMicro
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
                                        inspectViewer.openViewer(fileUrl, fileName, "架 #" + rack + " · " + appController.wheelLabel(wheelId) + " · " + receivedAtText)
                                    }
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: thumbnailView.count === 0
                                text: "暂无图片"
                                color: Theme.muted
                                font.family: Theme.fontSans
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
