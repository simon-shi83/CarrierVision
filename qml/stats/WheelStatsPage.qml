import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    // 轮系类别：false 为驱动轮 (1~8), true 为走行轮 (11~18)
    property bool isWalkWheel: false

    readonly property color currentThemeColor: isWalkWheel ? Theme.walkWheel : Theme.driveWheel
    readonly property string wheelTypeName: isWalkWheel ? "走行轮" : "驱动轮"
    readonly property int wheelBaseOffset: isWalkWheel ? 10 : 0

    property int detailWheel: 0
    property string detailResult: ""
    property var detailRackCounts: []
    property var detailRackPercents: []
    property int detailMaxCount: 1

    function openWheelRackDetail(wheelNumber, resultType) {
        detailWheel = wheelNumber
        detailResult = resultType
        var rows = (appController && appController.wheelRackResultStats) 
            ? (appController.wheelRackResultStats(gearBar.startDate, gearBar.endDate, wheelNumber, resultType) || []) 
            : []
        var counts = []
        var percents = []
        var maximum = 1
        for (var i = 0; i < 50; ++i) {
            counts.push(0)
            percents.push(0)
        }
        for (var j = 0; j < rows.length; ++j) {
            var row = rows[j]
            var rack = Number(row.rack)
            if (rack >= 1 && rack <= 50) {
                counts[rack - 1] = Number(row.count) || 0
                percents[rack - 1] = Number(row.percent) || 0
                maximum = Math.max(maximum, counts[rack - 1])
            }
        }
        detailRackCounts = counts
        detailRackPercents = percents
        detailMaxCount = maximum
        wheelRackDetailDialog.open()
    }

    function triggerSearch() {
        if (!appController) return
        var turns = []
        for (var k = 1; k <= 8; ++k) {
            turns.push(root.isWalkWheel ? (k + 10) : k)
        }
        appController.gearSumQuery(gearBar.startDate, gearBar.endDate, gearBar.rackno > 0 ? gearBar.rackno.toString() : "", turns)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 顶部复合查询栏 + 驱动/走行轮类别切换胶囊
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            WheelQueryBar {
                id: gearBar
                isWalkWheel: root.isWalkWheel
                Layout.fillWidth: true
                onSearchClicked: function(startDate, endDate, rackno, selectedTurns) {
                    if (appController)
                        appController.gearSumQuery(startDate, endDate, rackno.toString(), selectedTurns)
                }
                onResetClicked: {
                    if (appController)
                        root.triggerSearch()
                }
            }

            // 驱动轮 / 走行轮类别切换控件
            Rectangle {
                Layout.preferredHeight: 52
                implicitWidth: wheelTypeSwitchRow.implicitWidth + 12
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.color: Theme.borderMedium
                border.width: 1

                Row {
                    id: wheelTypeSwitchRow
                    anchors.centerIn: parent
                    spacing: 4

                    // 驱动轮按钮
                    Rectangle {
                        width: 96
                        height: 38
                        radius: Theme.radiusSm
                        color: !root.isWalkWheel ? Theme.driveWheelBg : (btnDriveMouse.containsMouse ? Theme.bgCardElevated : "transparent")
                        border.width: 1
                        border.color: !root.isWalkWheel ? Theme.driveWheel : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.driveWheel }
                            Text {
                                text: "驱动轮 (1~8)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: !root.isWalkWheel
                                color: !root.isWalkWheel ? Theme.driveWheel : Theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: btnDriveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.isWalkWheel) {
                                    root.isWalkWheel = false
                                    root.triggerSearch()
                                }
                            }
                        }
                    }

                    // 走行轮按钮
                    Rectangle {
                        width: 96
                        height: 38
                        radius: Theme.radiusSm
                        color: root.isWalkWheel ? Theme.walkWheelBg : (btnWalkMouse.containsMouse ? Theme.bgCardElevated : "transparent")
                        border.width: 1
                        border.color: root.isWalkWheel ? Theme.walkWheel : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.walkWheel }
                            Text {
                                text: "走行轮 (1~8)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.isWalkWheel
                                color: root.isWalkWheel ? Theme.walkWheel : Theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: btnWalkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.isWalkWheel) {
                                    root.isWalkWheel = true
                                    root.triggerSearch()
                                }
                            }
                        }
                    }
                }
            }
        }

        // 统计图表主体卡片
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLg
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.borderMedium

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // 标题与图例
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 4
                        height: 18
                        radius: 2
                        color: root.currentThemeColor
                    }

                    Label {
                        text: root.wheelTypeName + " (轮 1 ~ 8) 合格与异常对比直方图"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeH2
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    RowLayout {
                        spacing: 16
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 12; height: 12; radius: 3; color: Theme.ok }
                            Label { text: "OK 正常"; color: Theme.okLight; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        }
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 12; height: 12; radius: 3; color: Theme.ng }
                            Label { text: "NG 异常"; color: Theme.ngLight; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        }
                        Rectangle {
                            Layout.preferredHeight: 22
                            implicitWidth: chartHintRow.implicitWidth + 14
                            radius: Theme.radiusPill
                            color: Theme.bgCardElevated
                            border.color: Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                id: chartHintRow
                                anchors.centerIn: parent
                                spacing: 4
                                AppIcon { name: "icon_chart_bar"; size: 11; color: Theme.textMuted }
                                Text {
                                    text: "轻触直方柱下钻架号明细"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeTiny
                                }
                            }
                        }
                    }
                }

                // 绘图区域容器
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    Item {
                        id: chartArea
                        anchors.fill: parent
                        anchors.margins: 20

                        property var okCounts: [0, 0, 0, 0, 0, 0, 0, 0]
                        property var ngCounts: [0, 0, 0, 0, 0, 0, 0, 0]
                        property int maxCount: 1

                        function refreshData() {
                            if (!appController) return
                            var m = appController.gearSumResult
                            if (!m || typeof m.length === 'undefined' || m.length === 0) {
                                okCounts = [0, 0, 0, 0, 0, 0, 0, 0]
                                ngCounts = [0, 0, 0, 0, 0, 0, 0, 0]
                                maxCount = 1
                                return
                            }

                            var oks = [0, 0, 0, 0, 0, 0, 0, 0]
                            var ngs = [0, 0, 0, 0, 0, 0, 0, 0]
                            for (var i = 0; i < m.length; i++) {
                                var row = m[i]
                                if (!row) continue
                                var w = Number(row.wheel) || Number(row.w) || Number(row.turn) || 0
                                var ok = Number(row.ok) || Number(row.okCount) || 0
                                var ng = Number(row.ng) || Number(row.ngCount) || 0

                                if (root.isWalkWheel) {
                                    if (w >= 11 && w <= 18) {
                                        oks[w - 11] = ok
                                        ngs[w - 11] = ng
                                    }
                                } else {
                                    if (w >= 1 && w <= 8) {
                                        oks[w - 1] = ok
                                        ngs[w - 1] = ng
                                    }
                                }
                            }
                            okCounts = oks
                            ngCounts = ngs
                            var mm = 0
                            for (var j = 0; j < 8; j++) mm = Math.max(mm, oks[j], ngs[j])
                            maxCount = Math.max(1, mm)
                        }

                        Connections {
                            target: appController
                            function onGearSumResultChanged() { chartArea.refreshData() }
                        }

                        Component.onCompleted: chartArea.refreshData()

                        // 背景基准网格线
                        Column {
                            anchors.fill: parent
                            anchors.bottomMargin: 30
                            spacing: (height - 4) / 4
                            Repeater {
                                model: 5
                                Rectangle {
                                    width: chartArea.width
                                    height: 1
                                    color: Theme.borderSubtle
                                    opacity: 0.5
                                }
                            }
                        }

                        // 8 组直方柱 (自适应居中布局)
                        Row {
                            anchors.fill: parent
                            spacing: Math.max(8, (width - (8 * 64)) / 9)

                            Repeater {
                                model: 8
                                Item {
                                    width: 64
                                    height: parent.height

                                    readonly property real plotHeight: Math.max(0, height - 46)
                                    readonly property real okBarH: (chartArea.okCounts[index] / chartArea.maxCount) * plotHeight
                                    readonly property real ngBarH: (chartArea.ngCounts[index] / chartArea.maxCount) * plotHeight
                                    readonly property int actualWheelNumber: root.isWalkWheel ? (index + 11) : (index + 1)

                                    // OK 柱
                                    Rectangle {
                                        id: okBar
                                        width: 26
                                        height: parent.okBarH
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 30
                                        anchors.left: parent.left
                                        radius: Theme.radiusSm
                                        color: okMouse.containsMouse ? Theme.okLight : Theme.ok
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                        MouseArea {
                                            id: okMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openWheelRackDetail(actualWheelNumber, "OK")
                                            onDoubleClicked: root.openWheelRackDetail(actualWheelNumber, "OK")
                                        }
                                    }

                                    // NG 柱
                                    Rectangle {
                                        id: ngBar
                                        width: 26
                                        height: parent.ngBarH
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 30
                                        anchors.right: parent.right
                                        radius: Theme.radiusSm
                                        color: ngMouse.containsMouse ? Theme.ngLight : Theme.ng
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                        MouseArea {
                                            id: ngMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openWheelRackDetail(actualWheelNumber, "NG")
                                            onDoubleClicked: root.openWheelRackDetail(actualWheelNumber, "NG")
                                        }
                                    }

                                    // OK 数值标签
                                    Text {
                                        text: String(chartArea.okCounts[index])
                                        color: Theme.okLight
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        anchors.horizontalCenter: okBar.horizontalCenter
                                        anchors.bottom: okBar.top
                                        anchors.bottomMargin: 4
                                        visible: chartArea.okCounts[index] > 0
                                    }

                                    // NG 数值标签
                                    Text {
                                        text: String(chartArea.ngCounts[index])
                                        color: Theme.ngLight
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        anchors.horizontalCenter: ngBar.horizontalCenter
                                        anchors.bottom: ngBar.top
                                        anchors.bottomMargin: 4
                                        visible: chartArea.ngCounts[index] > 0
                                    }

                                    // X 轴轮位标签
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: 54
                                        height: 22
                                        radius: Theme.radiusPill
                                        color: Theme.bgCardElevated
                                        border.color: Theme.borderSubtle
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "轮 " + (index + 1)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeTiny
                                            font.bold: true
                                            color: root.currentThemeColor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 按架号明细下钻弹窗
    Dialog {
        id: wheelRackDetailDialog
        parent: Overlay.overlay
        modal: true
        width: Math.min(1080, root.width * 0.92)
        height: Math.min(820, root.height * 0.85)
        anchors.centerIn: parent
        title: root.wheelTypeName + " #" + root.detailWheel + " ╎ " + root.detailResult + " 判定 ╎ 50 架数据下钻明细"

        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
        }

        contentItem: DriveWheelRackDetail {
            startDate: gearBar.startDate
            endDate: gearBar.endDate
            wheelNumber: root.detailWheel
            resultType: root.detailResult
        }

        footer: Rectangle {
            implicitHeight: 52
            color: Theme.bgCardElevated
            radius: Theme.radiusLg
            RowLayout {
                anchors.fill: parent
                anchors.rightMargin: 16
                Item { Layout.fillWidth: true }
                ActionButton {
                    text: "关闭"
                    variant: "primary"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    onClicked: wheelRackDetailDialog.close()
                }
            }
        }
    }
}
