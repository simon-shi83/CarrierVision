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

    property int statsRequestId: -1
    // 图像总数（后端单次最多返回 200 张，超出时界面注明只显示最新部分）
    property int imageTotal: 0

    function loadStatistics() {
        if (!appController || !appController.requestStats || wheelNumber <= 0)
            return
        statsRequestId = appController.requestStats("wheelRackResultStats",
            [startDate, endDate, wheelNumber, normalizedResult()])
    }

    function applyStatistics(rows) {
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
                                  1, 200)
    }

    onStartDateChanged: loadStatistics()
    onEndDateChanged: loadStatistics()
    onWheelNumberChanged: loadStatistics()
    onResultTypeChanged: loadStatistics()
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

            // 顶栏汇总指示
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
                        text: "架轮判定下钻明细"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.fontMedium
                    }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Theme.borderMuted }
                    Label { text: "时间: " + (startDate || "--") + " ~ " + (endDate || "--"); color: Theme.textSoft; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular; font.pixelSize: Theme.fontCaption }
                    Label { text: "轮号: #" + wheelNumber; color: Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular; font.pixelSize: Theme.fontCaption }
                    Label {
                        text: "判定: " + normalizedResult()
                        color: normalizedResult() === "OK" ? Theme.ok : Theme.danger
                        font.weight: Theme.fontMedium
                        font.pixelSize: Theme.fontCaption
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: "共 " + rackRows.length + " 个架号有记录"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
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
                                Text { text: "轮号"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                                Text { text: "判定"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                                Text { text: "计数"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
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
                                radius: Theme.radiusMicro
                                color: selected ? Theme.pressed : (itemMouse.containsMouse ? Theme.surfaceAlt : "transparent")
                                border.width: 1
                                border.color: selected ? Theme.accent : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    Text { text: "#" + parent.parent.modelData.rack; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: parent.parent.selected ? Theme.accent : Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: String(root.wheelNumber); Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: Theme.textSoft; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: root.normalizedResult(); Layout.preferredWidth: 60; horizontalAlignment: Text.AlignHCenter; color: root.normalizedResult() === "OK" ? Theme.ok : Theme.danger; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
                                    Text { text: parent.parent.modelData.count; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: Theme.text; font.weight: Theme.fontMedium; font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular }
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
                                text: selectedRack > 0 ? "架号 #" + selectedRack + " 的检测原图" : "检测原图"
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
                                        inspectViewer.openViewer(fileUrl, fileName, "架 #" + rack + " ╎ 轮 #" + slot + " ╎ " + receivedAtText)
                                    }
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: thumbnailView.count === 0
                                text: selectedRack > 0 ? "暂无图片" : "请从左侧选择架号"
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
