import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    signal requestStats(string startDate, string endDate)

    // 轮系类别：false 为驱动轮 (1~8), true 为走行轮 (11~18)
    property bool isWalkWheel: false

    readonly property color currentThemeColor: isWalkWheel ? Theme.walkWheel : Theme.driveWheel
    readonly property string wheelTypeName: isWalkWheel ? "走行轮" : "驱动轮"
    readonly property int wheelTypeIndex: isWalkWheel ? 1 : 0
    readonly property var currentWheelTokens: isWalkWheel ? [11, 12, 13, 14, 15, 16, 17, 18] : [1, 2, 3, 4, 5, 6, 7, 8]

    property var dataModel: []
    property int detailRack: 0
    property string detailResult: ""
    property var detailOkCounts: [0, 0, 0, 0, 0, 0, 0, 0]
    property var detailNgCounts: [0, 0, 0, 0, 0, 0, 0, 0]
    property var detailLossRates: [0, 0, 0, 0, 0, 0, 0, 0]
    property real detailMaxValue: 1

    function loadStats(startDate, endDate) {
        if (!appController) return
        var stats = root.isWalkWheel 
            ? (appController.walkingWheelRackStats ? appController.walkingWheelRackStats(startDate, endDate) : [])
            : (appController.driveWheelRackStats ? appController.driveWheelRackStats(startDate, endDate) : [])
        updateData(stats || [])
    }

    function generateRackCsv() {
        var csv = "架号,OK数,NG数,损耗率(%)\n"
        for (var i = 0; i < 50; ++i) {
            var row = dataModel && dataModel[i] ? dataModel[i] : {}
            var rack = Number(row.rack) || (i + 1)
            var ok = Number(row.ok) || 0
            var ng = Number(row.ng) || 0
            var loss = Number(row.loss) || 0
            csv += rack + "," + ok + "," + ng + "," + loss.toFixed(1) + "\n"
        }
        return csv
    }

    function openRackDetail(rack) {
        detailRack = rack
        detailDialog.open()
        if (appController)
            appController.gearSumQuery(dateBar.startDate, dateBar.endDate, String(rack), root.currentWheelTokens)
    }

    function openRackWheelStats(rack, resultType) {
        detailRack = rack
        detailResult = resultType
        rackWheelStatsDialog.open()
    }

    function refreshRackDetail() {
        if (detailRack <= 0 || !appController) return
        var rows = appController.gearSumResult || []
        var oks = [0, 0, 0, 0, 0, 0, 0, 0]
        var ngs = [0, 0, 0, 0, 0, 0, 0, 0]
        var losses = [0, 0, 0, 0, 0, 0, 0, 0]
        var maximum = 1
        for (var i = 0; i < rows.length; ++i) {
            var row = rows[i]
            var wheel = Number(row.wheel)
            if (root.isWalkWheel) {
                if (wheel < 11 || wheel > 18) continue
                var idx = wheel - 11
                oks[idx] = Number(row.ok) || 0
                ngs[idx] = Number(row.ng) || 0
                losses[idx] = oks[idx] + ngs[idx] > 0
                        ? ngs[idx] * 100 / (oks[idx] + ngs[idx]) : 0
                maximum = Math.max(maximum, oks[idx], ngs[idx], losses[idx])
            } else {
                if (wheel < 1 || wheel > 8) continue
                var index = wheel - 1
                oks[index] = Number(row.ok) || 0
                ngs[index] = Number(row.ng) || 0
                losses[index] = oks[index] + ngs[index] > 0
                        ? ngs[index] * 100 / (oks[index] + ngs[index]) : 0
                maximum = Math.max(maximum, oks[index], ngs[index], losses[index])
            }
        }
        detailOkCounts = oks
        detailNgCounts = ngs
        detailLossRates = losses
        detailMaxValue = maximum
    }

    Connections {
        target: appController
        function onGearSumResultChanged() {
            if (detailDialog.visible) root.refreshRackDetail()
        }
    }

    function updateData(arr) {
        dataModel = arr
        chartArea.updateFromModel(arr)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 顶栏：日期查询栏 + 驱动/走行轮类别切换胶囊
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            DateQueryBar {
                id: dateBar
                Layout.fillWidth: true
                wheelType: root.wheelTypeIndex
                exportCsvContent: root.generateRackCsv()
                onSearchClicked: function(startDate, endDate) {
                    root.requestStats(startDate, endDate)
                    root.loadStats(startDate, endDate)
                }
            }

            // 驱动/走行轮类别切换胶囊
            Rectangle {
                Layout.preferredHeight: 52
                implicitWidth: rackTypeSwitchRow.implicitWidth + 12
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.color: Theme.borderMedium
                border.width: 1

                Row {
                    id: rackTypeSwitchRow
                    anchors.centerIn: parent
                    spacing: 4

                    // 驱动轮
                    Rectangle {
                        width: 104
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
                                text: "驱动轮 (50架)"
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
                                    root.loadStats(dateBar.startDate, dateBar.endDate)
                                }
                            }
                        }
                    }

                    // 走行轮
                    Rectangle {
                        width: 104
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
                                text: "走行轮 (50架)"
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
                                    root.loadStats(dateBar.startDate, dateBar.endDate)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 主体图表卡片
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
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle { width: 4; height: 18; radius: 2; color: root.currentThemeColor }
                    Label {
                        text: root.wheelTypeName + " (50 架全景) 点检统计与损耗率分布"
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
                            Rectangle { width: 10; height: 10; radius: 2; color: Theme.ok }
                            Label { text: "OK 正常"; color: Theme.okLight; font.pixelSize: Theme.fontSizeSmall }
                        }
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 10; height: 10; radius: 2; color: Theme.ng }
                            Label { text: "NG 异常"; color: Theme.ngLight; font.pixelSize: Theme.fontSizeSmall }
                        }
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 10; height: 10; radius: 2; color: Theme.warning }
                            Label { text: "损耗率 (%)"; color: Theme.warningLight; font.pixelSize: Theme.fontSizeSmall }
                        }
                        Label { text: "💡 双击柱体下钻架轮明细"; color: Theme.textMuted; font.pixelSize: Theme.fontSizeTiny }
                    }
                }

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
                        anchors.margins: 14
                        readonly property real groupWidth: width / 50
                        property var okCounts: []
                        property var ngCounts: []
                        property var lossRates: []
                        property real maxValue: 1

                        function clearData() {
                            var zeros = []
                            for (var i = 0; i < 50; ++i) zeros.push(0)
                            okCounts = zeros.slice()
                            ngCounts = zeros.slice()
                            lossRates = zeros.slice()
                            maxValue = 1
                        }

                        function updateFromModel(rows) {
                            clearData()
                            if (!rows || typeof rows.length === "undefined") return
                            var oks = okCounts.slice()
                            var ngs = ngCounts.slice()
                            var losses = lossRates.slice()
                            var maximum = 1
                            for (var i = 0; i < rows.length; ++i) {
                                var row = rows[i]
                                var rack = Number(row.rack)
                                if (rack < 1 || rack > 50) continue
                                var index = rack - 1
                                oks[index] = Number(row.ok) || 0
                                ngs[index] = Number(row.ng) || 0
                                losses[index] = Number(row.loss) || 0
                                maximum = Math.max(maximum, oks[index], ngs[index], losses[index])
                            }
                            okCounts = oks
                            ngCounts = ngs
                            lossRates = losses
                            maxValue = maximum
                        }

                        Component.onCompleted: clearData()

                        Repeater {
                            model: 50
                            Item {
                                width: chartArea.groupWidth
                                height: chartArea.height
                                x: index * chartArea.groupWidth
                                readonly property real plotHeight: Math.max(0, height - 38)

                                Rectangle {
                                    width: Math.max(2, parent.width * 0.24)
                                    height: (chartArea.okCounts[index] / chartArea.maxValue) * parent.plotHeight
                                    anchors.left: parent.left
                                    anchors.leftMargin: parent.width * 0.06
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 22
                                    color: Theme.ok
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onDoubleClicked: root.openRackWheelStats(index + 1, "OK")
                                    }
                                }

                                Rectangle {
                                    width: Math.max(2, parent.width * 0.24)
                                    height: (chartArea.ngCounts[index] / chartArea.maxValue) * parent.plotHeight
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 22
                                    color: Theme.ng
                                    radius: 2
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onDoubleClicked: root.openRackWheelStats(index + 1, "NG")
                                    }
                                }

                                Rectangle {
                                    width: Math.max(2, parent.width * 0.24)
                                    height: (chartArea.lossRates[index] / chartArea.maxValue) * parent.plotHeight
                                    anchors.right: parent.right
                                    anchors.rightMargin: parent.width * 0.06
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 22
                                    color: Theme.warning
                                    radius: 2
                                }

                                Text {
                                    text: String(index + 1)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root.loadStats(dateBar.startDate, dateBar.endDate)
        })
    }

    Dialog {
        id: rackWheelStatsDialog
        parent: Overlay.overlay
        modal: true
        width: Math.min(1180, root.width * 0.94)
        height: Math.min(680, root.height * 0.88)
        anchors.centerIn: parent
        title: "架号 #" + root.detailRack + " ╎ " + root.detailResult + " 判定 ╎ " + root.wheelTypeName + "明细"

        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
        }

        contentItem: RackWheelStats {
            startDate: dateBar.startDate
            endDate: dateBar.endDate
            rackNumber: root.detailRack
            resultType: root.detailResult
            wheelType: root.wheelTypeIndex
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
                    onClicked: rackWheelStatsDialog.close()
                }
            }
        }
    }

    Dialog {
        id: detailDialog
        parent: Overlay.overlay
        modal: true
        title: "架号 #" + root.detailRack + " ╎ " + root.wheelTypeName + " 8 轮直方明细"
        width: Math.min(920, root.width * 0.84)
        height: Math.min(580, root.height * 0.80)
        anchors.centerIn: parent

        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Label { text: "统计时间: " + dateBar.startDate + " ~ " + dateBar.endDate; color: Theme.textSecondary; font.family: Theme.fontMono }
                Item { Layout.fillWidth: true }
                Label { text: "OK: 绿色"; color: Theme.okLight }
                Label { text: "NG: 红色"; color: Theme.ngLight }
                Label { text: "损耗率: 琥珀金"; color: Theme.warningLight }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgInput
                radius: Theme.radiusMd
                border.color: Theme.borderSubtle
                border.width: 1

                Item {
                    id: detailPlot
                    anchors.fill: parent
                    anchors.margins: 14

                    Repeater {
                        model: 8
                        Item {
                            width: detailPlot.width / 8
                            height: detailPlot.height
                            x: index * width
                            readonly property real plotHeight: Math.max(0, height - 44)

                            Rectangle { width: parent.width * 0.22; height: (root.detailOkCounts[index] / root.detailMaxValue) * parent.plotHeight; anchors.left: parent.left; anchors.leftMargin: parent.width * 0.10; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; color: Theme.ok; radius: 2 }
                            Rectangle { width: parent.width * 0.22; height: (root.detailNgCounts[index] / root.detailMaxValue) * parent.plotHeight; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; color: Theme.ng; radius: 2 }
                            Rectangle { width: parent.width * 0.22; height: (root.detailLossRates[index] / root.detailMaxValue) * parent.plotHeight; anchors.right: parent.right; anchors.rightMargin: parent.width * 0.10; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; color: Theme.warning; radius: 2 }

                            Text { text: String(root.detailOkCounts[index]); visible: root.detailOkCounts[index] > 0; anchors.horizontalCenter: parent.left; anchors.horizontalCenterOffset: parent.width * 0.21; anchors.bottom: parent.bottom; anchors.bottomMargin: 30 + (root.detailOkCounts[index] / root.detailMaxValue) * parent.plotHeight; color: Theme.okLight; font.bold: true; font.family: Theme.fontMono; font.pixelSize: 10 }
                            Text { text: String(root.detailNgCounts[index]); visible: root.detailNgCounts[index] > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 30 + (root.detailNgCounts[index] / root.detailMaxValue) * parent.plotHeight; color: Theme.ngLight; font.bold: true; font.family: Theme.fontMono; font.pixelSize: 10 }
                            Text { text: Number(root.detailLossRates[index]).toFixed(1) + "%"; visible: root.detailLossRates[index] > 0; anchors.horizontalCenter: parent.right; anchors.horizontalCenterOffset: -parent.width * 0.21; anchors.bottom: parent.bottom; anchors.bottomMargin: 30 + (root.detailLossRates[index] / root.detailMaxValue) * parent.plotHeight; color: Theme.warningLight; font.bold: true; font.family: Theme.fontMono; font.pixelSize: 10 }
                            Text { text: "轮 " + (index + 1); anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; color: Theme.textPrimary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        }
                    }
                }
            }
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
                    onClicked: detailDialog.close()
                }
            }
        }
    }
}
