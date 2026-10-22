import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    property var rackRows: []
    property var wheelRows: []
    property int selectedRack: 0
    property int selectedWheel: 0
    property int maxRackNg: 1

    property int rackRequestId: -1
    property int wheelRequestId: -1
    property int imageRequestId: -1
    property int dispositionRequestId: -1
    property int imagePage: 1
    property int imageTotal: 0
    property var currentImage: ({})
    property string queryStart: ""
    property string queryEnd: ""
    property string operationMessage: ""
    property bool preserveWheel: false

    function resetImage() {
        imageRequestId = -1
        imagePage = 1
        imageTotal = 0
        currentImage = ({})
        viewer.visible = false
    }

    function disposeWheel(wheel, kind) {
        if (dispositionRequestId !== -1) return
        operationMessage = "正在保存处置状态…"
        dispositionRequestId = appController.requestAlertOperation(kind, queryStart, queryEnd,
                                                                  selectedRack, wheel, 1)
    }

    function refreshRackCounts() {
        rackRequestId = appController.requestAlertOperation("racks", queryStart, queryEnd, 0, 0, 1)
    }

    function loadRackStatistics() {
        if (!appController || !appController.requestAlertOperation)
            return
        queryStart = dateBar.startDate
        queryEnd = dateBar.endDate
        wheelRequestId = -1
        operationMessage = ""
        rackRows = []
        selectedRack = 0
        selectedWheel = 0
        wheelRows = []
        resetImage()
        refreshRackCounts()
    }

    function applyRackStatistics(stats) {
        var rows = []
        var maxVal = 1
        for (var i = 0; i < stats.length; ++i) {
            var row = stats[i]
            var count = Number(row.count)
            if (count > 0) {
                rows.push({ rack: Number(row.rack), count: count,
                            pending: Number(row.pending), handled: Number(row.handled) })
                if (count > maxVal) maxVal = count
            }
        }
        maxRackNg = maxVal
        rackRows = rows
        if (selectedRack > 0) return
        selectedWheel = 0
        wheelRows = []
        resetImage()
        if (rows.length > 0)
            loadWheelStatistics(rows[0].rack)
    }

    function loadWheelStatistics(rack, preserve) {
        preserveWheel = preserve === true && selectedRack === rack
        selectedRack = rack
        if (!preserveWheel) {
            selectedWheel = 0
            wheelRows = []
            resetImage()
        }
        wheelRequestId = appController.requestAlertOperation("groups", queryStart, queryEnd,
                                                             rack, 0, 1)
    }

    function applyWheelStatistics(stats) {
        wheelRows = stats
        if (preserveWheel && selectedWheel > 0) return
        if (stats.length > 0) loadImages(Number(stats[0].wheel))
        else resetImage()
    }

    Connections {
        target: appController
        function onAlertOperationFinished(requestId, result) {
            if (requestId === root.rackRequestId) {
                root.rackRequestId = -1
                if (result.ok) root.applyRackStatistics(result.rows || [])
                else root.operationMessage = result.error
            } else if (requestId === root.dispositionRequestId) {
                root.dispositionRequestId = -1
                root.operationMessage = result.ok
                    ? "已保存，本次处置 " + result.affected + " 条异常记录"
                    : result.error
                if (result.ok) root.refreshRackCounts()
                if (root.selectedRack > 0) root.loadWheelStatistics(root.selectedRack, true)
            } else if (requestId === root.wheelRequestId) {
                root.wheelRequestId = -1
                if (result.ok) root.applyWheelStatistics(result.rows || [])
                else root.operationMessage = result.error
            } else if (requestId === root.imageRequestId) {
                root.imageRequestId = -1
                if (result.ok) {
                    root.imagePage = Number(result.page)
                    root.imageTotal = Number(result.total)
                    root.currentImage = result.image || ({})
                } else root.operationMessage = result.error
            }
        }
    }

    function loadImages(wheel) {
        selectedWheel = wheel
        resetImage()
        loadImagePage(1)
    }

    function loadImagePage(page) {
        if (selectedRack <= 0 || selectedWheel <= 0) return
        imageRequestId = appController.requestAlertOperation("image", queryStart, queryEnd,
                                                             selectedRack, selectedWheel, page)
    }

    function generateCsv() {
        var csv = "wheel_type,position_range,轮系类别,架号,NG数量,未处理频次,已处理频次\n"
        var prefix = "all,1～16,全部轮位,"
        for (var i = 0; i < rackRows.length; ++i)
            csv += prefix + rackRows[i].rack + "," + rackRows[i].count + "," + rackRows[i].pending + "," + rackRows[i].handled + "\n"
        return csv
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 顶栏：日期查询栏（全部轮位）
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            DateQueryBar {
                id: dateBar
                defaultRangeDays: 7
                Layout.fillWidth: true
                wheelType: -1
                exportCsvContent: root.generateCsv()
                onSearchClicked: function(startDate, endDate) {
                    root.loadRackStatistics()
                }
                onResetClicked: root.loadRackStatistics()
            }

        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // 1. 架号 NG 汇总栏
            Rectangle {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                radius: Theme.radiusMedium
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 3; height: 14; radius: 1.5; color: Theme.danger }
                        Label {
                            text: "架号异常"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontMedium
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        color: Theme.surfaceAlt
                        radius: Theme.radiusMicro

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { text: "架号"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                            Text { text: "未处理频次"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                            Text { text: "已处理频次"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                        }
                    }

                    ListView {
                        id: rackList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.rackRows
                        clip: true
                        spacing: 4

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.selectedRack === modelData.rack
                            width: rackList.width
                            height: 38
                            radius: Theme.radiusSmall
                            color: selected ? Theme.pressed : (itemMouse.containsMouse ? Theme.surfaceAlt : Theme.fieldFill)
                            border.width: 1
                            border.color: selected ? Theme.accent : "transparent"
                            clip: true

                            // 异常频次微热力图底色 (数据可视化深度赋能)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(4, (modelData.count / Math.max(1, root.maxRackNg)) * parent.width)
                                color: Theme.dangerSoft
                                opacity: parent.selected ? 0.45 : 0.25
                                radius: Theme.radiusSmall
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                // 排行徽章
                                Rectangle {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    radius: 9
                                    color: index < 3 ? Theme.dangerSoft : Theme.surfaceAlt
                                    border.color: index < 3 ? Theme.dangerBorder : Theme.borderMuted
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: String(index + 1)
                                        color: index < 3 ? Theme.danger : Theme.muted
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.pixelSize: Theme.fontMicro
                                        font.weight: Theme.fontMedium
                                    }
                                }

                                Text {
                                    text: "架 #" + parent.parent.modelData.rack
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    color: parent.parent.selected ? Theme.accent : Theme.text
                                    font.weight: Theme.fontMedium
                                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                }

                                Rectangle {
                                    Layout.preferredWidth: 80
                                    Layout.preferredHeight: 22
                                    radius: Theme.radiusPill
                                    color: Theme.dangerSoft
                                    border.color: Theme.dangerBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.parent.modelData.pending
                                        color: Theme.danger
                                        font.weight: Theme.fontMedium
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }
                                Text {
                                    text: parent.parent.modelData.handled
                                    Layout.preferredWidth: 80
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.text
                                    font.weight: Theme.fontMedium
                                    font.family: Theme.fontSans
                                    font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.loadWheelStatistics(parent.modelData.rack)
                            }
                        }

                        // 优雅的零报警空状态
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: rackList.count === 0
                            spacing: 8

                            AppIcon {
                                Layout.alignment: Qt.AlignHCenter
                                name: "icon_check_circle"
                                size: 36
                                color: Theme.ok
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: "全区间运行正常"
                                color: Theme.ok
                                font.family: Theme.fontSans
                                font.weight: Theme.fontMedium
                                font.pixelSize: Theme.fontCaption
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: "当前时间范围无异常记录"
                                color: Theme.muted
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontMicro
                            }
                        }
                    }
                }
            }

            // 2. 轮位 NG 汇总栏
            Rectangle {
                Layout.preferredWidth: 330
                Layout.fillHeight: true
                radius: Theme.radiusMedium
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 3; height: 14; radius: 1.5; color: Theme.danger }
                        Label {
                            text: selectedRack > 0 ? "架 #" + selectedRack + " · 异常统计" : "异常统计"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontMedium
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        color: Theme.surfaceAlt
                        radius: Theme.radiusMicro

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { text: "轮号"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.textSoft; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                            Text { text: "NG 频次"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.danger; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
                        }
                    }

                    ListView {
                        id: wheelList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.wheelRows
                        clip: true
                        spacing: 4

                        delegate: Rectangle {
                            id: wheelDelegate
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.selectedWheel === modelData.wheel
                            width: wheelList.width
                            height: 96
                            radius: Theme.radiusSmall
                            color: selected ? Theme.pressed : (wheelMouse.containsMouse ? Theme.surfaceAlt : Theme.fieldFill)
                            border.width: 1
                            border.color: selected ? Theme.accent : "transparent"
                            clip: true

                            MouseArea {
                                id: wheelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.loadImages(wheelDelegate.modelData.wheel)
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.space2
                                spacing: Theme.space1
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: appController.wheelLabel(wheelDelegate.modelData.wheel)
                                        Layout.fillWidth: true
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.fontMedium
                                    }
                                    Label {
                                        text: "NG " + wheelDelegate.modelData.count
                                        color: Theme.textSoft
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontCaption
                                        font.features: Theme.fontFeaturesTabular
                                    }
                                }
                                Label {
                                    text: "待处置 " + wheelDelegate.modelData.pending
                                          + " · 已处理 " + wheelDelegate.modelData.handled
                                          + " · 误报 " + wheelDelegate.modelData.falseAlarm
                                    color: Theme.textSoft
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontCaption
                                    font.features: Theme.fontFeaturesTabular
                                }
                                RowLayout {
                                    spacing: Theme.space2
                                    Repeater {
                                        model: [{label: "已处理", kind: "handled"}, {label: "误报", kind: "falseAlarm"}]
                                        delegate: ActionButton {
                                            required property var modelData
                                            text: modelData.label
                                            variant: "secondary"
                                            implicitHeight: 28
                                            hoverTextColor: Theme.text
                                            hoverColor: Theme.hover
                                            enabled: Number(wheelDelegate.modelData.pending) > 0
                                                     && root.dispositionRequestId === -1
                                            onClicked: root.disposeWheel(Number(wheelDelegate.modelData.wheel), modelData.kind)
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: selectedRack > 0 && wheelList.count === 0
                            spacing: 6
                            AppIcon {
                                Layout.alignment: Qt.AlignHCenter
                                name: "icon_check_circle"
                                size: 28
                                color: Theme.ok
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: "该架号全轮检测正常"
                                color: Theme.ok
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                            }
                        }
                    }
                }
            }

            // 3. 异常原图画廊
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusMedium
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 3; height: 14; radius: 1.5; color: Theme.borderStrong }
                        Label {
                            text: selectedWheel > 0 ? "架 #" + selectedRack + " · " + appController.wheelLabel(selectedWheel) + " 异常证据链" : "异常点检原图"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontMedium
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.operationMessage || "操作仅处置当前日期范围内的未处置记录；已处理表示已换轮"
                        wrapMode: Text.WordWrap
                        color: Theme.textSoft
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.surfaceAlt
                        radius: Theme.radiusSmall
                        Image {
                            id: evidenceImage
                            anchors.fill: parent
                            anchors.margins: Theme.space2
                            source: root.currentImage.url || ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: root.imageRequestId === -1
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: evidenceImage.status === Image.Ready
                                onClicked: viewer.openViewer(root.currentImage.url, root.currentImage.name,
                                                              root.currentImage.time)
                            }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: root.imageRequestId !== -1 ? "正在加载…"
                                  : (root.imageTotal === 0 ? "当前轮位没有异常图像记录"
                                     : "图片尚未到达或文件不可用")
                            visible: root.imageRequestId !== -1 || evidenceImage.status !== Image.Ready
                            color: Theme.muted
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.currentImage.name || ""
                        elide: Text.ElideMiddle
                        color: Theme.textSoft
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: root.currentImage.time || ""
                            color: Theme.textSoft
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                            font.features: Theme.fontFeaturesTabular
                        }
                        Item { Layout.fillWidth: true }
                        ActionButton {
                            text: "上一幅"
                            variant: "secondary"
                            hoverTextColor: Theme.text
                            hoverColor: Theme.hover
                            enabled: root.imagePage > 1 && root.imageRequestId === -1
                            onClicked: root.loadImagePage(root.imagePage - 1)
                        }
                        Label {
                            text: (root.imageTotal > 0 ? root.imagePage : 0) + " / " + root.imageTotal
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                            font.features: Theme.fontFeaturesTabular
                        }
                        ActionButton {
                            text: "下一幅"
                            variant: "secondary"
                            hoverTextColor: Theme.text
                            hoverColor: Theme.hover
                            enabled: root.imagePage < root.imageTotal && root.imageRequestId === -1
                            onClicked: root.loadImagePage(root.imagePage + 1)
                        }
                    }
                }
            }
        }
    }

    ZoomOverlay {
        id: viewer
        anchors.fill: parent
    }

    Component.onCompleted: Qt.callLater(loadRackStatistics)
}
