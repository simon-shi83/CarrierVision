import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    // 轮系类别：false 为驱动轮（9～16）, true 为走行轮（1～8）
    property bool isWalkWheel: false
    readonly property color currentThemeColor: isWalkWheel ? Theme.walkWheel : Theme.driveWheel
    readonly property string wheelTypeName: isWalkWheel ? "走行轮" : "驱动轮"
    readonly property int wheelTypeIndex: isWalkWheel ? 1 : 0

    property var rackRows: []
    property var wheelRows: []
    property int selectedRack: 0
    property int selectedWheel: 0
    property int maxRackNg: 1
    property int maxWheelNg: 1

    property int rackRequestId: -1
    property int wheelRequestId: -1

    function loadRackStatistics() {
        if (!appController || !appController.requestStats)
            return
        wheelRequestId = -1
        rackRequestId = appController.requestStats(
            root.isWalkWheel ? "walkingWheelRackStats" : "driveWheelRackStats",
            [dateBar.startDate, dateBar.endDate])
    }

    function applyRackStatistics(stats) {
        var rows = []
        var maxVal = 1
        for (var i = 0; i < stats.length; ++i) {
            var row = stats[i]
            var count = Number(row.ng)
            if (count > 0) {
                rows.push({ rack: Number(row.rack), count: count })
                if (count > maxVal) maxVal = count
            }
        }
        maxRackNg = maxVal
        rackRows = rows
        selectedRack = 0
        selectedWheel = 0
        wheelRows = []
        if (appController.clearSearch)
            appController.clearSearch()
        if (rows.length > 0)
            loadWheelStatistics(rows[0].rack)
    }

    function loadWheelStatistics(rack) {
        selectedRack = rack
        selectedWheel = 0
        wheelRows = []
        if (!appController || !appController.requestStats)
            return
        wheelRequestId = appController.requestStats("rackWheelResultStats",
            [dateBar.startDate, dateBar.endDate, rack, "NG", root.wheelTypeIndex])
    }

    function applyWheelStatistics(stats) {
        var rows = []
        var maxVal = 1
        for (var i = 0; i < stats.length; ++i) {
            var row = stats[i]
            var count = Number(row.count)
            if (count > 0) {
                rows.push({ wheel: Number(row.wheel), count: count })
                if (count > maxVal) maxVal = count
            }
        }
        maxWheelNg = maxVal
        wheelRows = rows
        if (rows.length > 0)
            loadImages(rows[0].wheel)
        else if (appController.clearSearch)
            appController.clearSearch()
    }

    Connections {
        target: appController
        function onStatsReady(requestId, kind, result) {
            if (requestId === root.rackRequestId)
                root.applyRackStatistics(result || [])
            else if (requestId === root.wheelRequestId)
                root.applyWheelStatistics(result || [])
        }
    }

    function loadImages(wheel) {
        selectedWheel = wheel
        if (!appController || !appController.searchPaged || selectedRack <= 0)
            return
        appController.searchPaged(dateBar.startDate, dateBar.endDate, "", selectedRack,
                                  String(wheel), "0", 1, 200)
    }

    function generateCsv() {
        var csv = "wheel_type,position_range,轮系类别,架号,NG数量\n"
        var prefix = (root.isWalkWheel ? "walk,1～8," : "drive,9～16,") + root.wheelTypeName + ","
        for (var i = 0; i < rackRows.length; ++i)
            csv += prefix + rackRows[i].rack + "," + rackRows[i].count + "\n"
        return csv
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
                exportCsvContent: root.generateCsv()
                onSearchClicked: function(startDate, endDate) {
                    root.loadRackStatistics()
                }
                onResetClicked: root.loadRackStatistics()
            }

            // 驱动 / 走行轮类别切换胶囊
            Rectangle {
                Layout.preferredHeight: 52
                implicitWidth: wheelTypeSwitchRow.implicitWidth + 12
                radius: Theme.radiusSmall
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                Row {
                    id: wheelTypeSwitchRow
                    anchors.centerIn: parent
                    spacing: 4

                    // 驱动轮
                    Rectangle {
                        width: 96
                        height: 38
                        radius: Theme.radiusMicro
                        color: !root.isWalkWheel ? Theme.driveWheelSoft : (btnDriveMouse.containsMouse ? Theme.surfaceAlt : "transparent")
                        border.width: 1
                        border.color: !root.isWalkWheel ? Theme.driveWheel : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.driveWheel }
                            Text {
                                text: "驱动轮（9～16）"
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                                font.weight: (!root.isWalkWheel) ? Theme.fontMedium : Theme.fontRegular
                                color: !root.isWalkWheel ? Theme.driveWheel : Theme.textSoft
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
                                    root.loadRackStatistics()
                                }
                            }
                        }
                    }

                    // 走行轮
                    Rectangle {
                        width: 106
                        height: 38
                        radius: Theme.radiusMicro
                        color: root.isWalkWheel ? Theme.walkWheelSoft : (btnWalkMouse.containsMouse ? Theme.surfaceAlt : "transparent")
                        border.width: 1
                        border.color: root.isWalkWheel ? Theme.walkWheel : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.walkWheel }
                            Text {
                                text: "走行轮（1～8）"
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                                font.weight: (root.isWalkWheel) ? Theme.fontMedium : Theme.fontRegular
                                color: root.isWalkWheel ? Theme.walkWheel : Theme.textSoft
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
                                    root.loadRackStatistics()
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // 1. 架号 NG 汇总栏
            Rectangle {
                Layout.preferredWidth: 220
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
                            text: root.wheelTypeName + " · 架号异常"
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
                            Text { text: "NG 频次"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignHCenter; font.weight: Theme.fontMedium; color: Theme.danger; font.family: Theme.fontSans; font.pixelSize: Theme.fontCaption }
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
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 22
                                    radius: Theme.radiusPill
                                    color: Theme.dangerSoft
                                    border.color: Theme.dangerBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.parent.modelData.count
                                        color: Theme.danger
                                        font.weight: Theme.fontMedium
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.pixelSize: Theme.fontCaption
                                    }
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
                Layout.preferredWidth: 220
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
                            text: selectedRack > 0 ? "架 #" + selectedRack + " · " + root.wheelTypeName + "异常" : root.wheelTypeName + "异常统计"
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
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.selectedWheel === modelData.wheel
                            width: wheelList.width
                            height: 38
                            radius: Theme.radiusSmall
                            color: selected ? Theme.pressed : (wheelMouse.containsMouse ? Theme.surfaceAlt : Theme.fieldFill)
                            border.width: 1
                            border.color: selected ? Theme.accent : "transparent"
                            clip: true

                            // 轮位频次热力条
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(4, (modelData.count / Math.max(1, root.maxWheelNg)) * parent.width)
                                color: Theme.dangerSoft
                                opacity: parent.selected ? 0.45 : 0.25
                                radius: Theme.radiusSmall
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    text: appController.wheelLabel(parent.parent.modelData.wheel)
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    color: parent.parent.selected ? Theme.accent : Theme.text
                                    font.weight: Theme.fontMedium
                                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                }
                                Rectangle {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 22
                                    radius: Theme.radiusPill
                                    color: Theme.dangerSoft
                                    border.color: Theme.dangerBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.parent.modelData.count
                                        color: Theme.danger
                                        font.weight: Theme.fontMedium
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }
                            }

                            MouseArea {
                                id: wheelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.loadImages(parent.modelData.wheel)
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
                        Rectangle {
                            Layout.preferredHeight: 22
                            implicitWidth: galleryHintRow.implicitWidth + 14
                            radius: Theme.radiusPill
                            color: Theme.surfaceAlt
                            border.color: Theme.borderMuted
                            border.width: 1

                            RowLayout {
                                id: galleryHintRow
                                anchors.centerIn: parent
                                spacing: 4
                                AppIcon { name: "icon_eye"; size: 11; color: Theme.muted }
                                Text {
                                    text: "轻触卡片查看大图证据"
                                    color: Theme.muted
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontMicro
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ImageGridView {
                            anchors.fill: parent
                            model: appController ? appController.searchImagesModel : null
                            columns: Math.max(1, Math.floor(width / 220))
                            onImageClicked: function(title, date, imageUrl) {
                                viewer.openViewer(imageUrl, title, date)
                            }
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
