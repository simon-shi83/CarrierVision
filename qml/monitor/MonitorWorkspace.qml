import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../home"

Item {
    id: root
    anchors.fill: parent

    property var statusByCell: ({})
    property var photoCountByRack: ({})
    property string lastUpdated: ""
    property int hoveredRack: -1
    property int hoveredWheel: -1

    function cellKey(rack, wheel) {
        return rack + ":" + wheel
    }

    property int statusRequestId: -1
    property int photoCountRequestId: -1

    function refreshStatus() {
        if (!appController || !appController.requestStats)
            return
        statusRequestId = appController.requestStats("rackWheelMonitorStatus", [])
        photoCountRequestId = appController.requestStats("rackPhotoCounts", [])
    }

    function applyStatus(latest) {
        var cells = ({})
        for (var i = 0; i < latest.length; ++i) {
            var item = latest[i]
            cells[cellKey(item.rack, item.wheel)] = item
        }
        statusByCell = cells
        lastUpdated = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
    }

    function applyPhotoCounts(photoCounts) {
        var counts = ({})
        for (var j = 0; j < photoCounts.length; ++j)
            counts[photoCounts[j].rack] = Number(photoCounts[j].count) || 0
        photoCountByRack = counts
    }

    function openLatestImage(rackNumber, wheelNumber, wheelLabel) {
        if (!appController || !appController.latestRackWheelMonitorImage)
            return

        var image = appController.latestRackWheelMonitorImage(rackNumber, wheelNumber)
        if (!image.filePath || String(image.filePath).length === 0)
            return

        var normalizedPath = String(image.filePath).replace(/\\/g, "/")
        var sourceUrl = /^[a-zA-Z]:\//.test(normalizedPath)
                ? "file:///" + normalizedPath : normalizedPath
        imagePreview.openViewer(sourceUrl,
                "架号 #" + rackNumber + " ╎ " + wheelLabel,
                "最新检测判定: " + (image.result === 1 ? "OK 正常" : "NG 异常") + " ╎ 采集时间: " + image.time)
    }

    readonly property var wheelRows: {
        var rows = [];
        for (var positionNo = 1; positionNo <= 16; ++positionNo) {
            var raw = appController.wheelRawId(positionNo);
            rows.push({label: appController.wheelLabel(raw), wheel: raw, isDrive: raw >= 9});
        }
        return rows;
    }
    readonly property var wheelColumns: wheelRows

    Component.onCompleted: refreshStatus()

    Connections {
        target: appController
        function onRackWheelMonitorUpdated() {
            root.refreshStatus()
        }
        function onStatsReady(requestId, kind, result) {
            if (requestId === root.statusRequestId)
                root.applyStatus(result || [])
            else if (requestId === root.photoCountRequestId)
                root.applyPhotoCounts(result || [])
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // 顶栏遥测指示
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    width: 4
                    height: 18
                    radius: 2
                    color: Theme.borderStrong
                }

                Label {
                    text: "16 轮位 × 50 架 全景遥测热力矩阵"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontMedium
                }

                // 状态图例
                RowLayout {
                    Layout.leftMargin: 12
                    spacing: 12

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.ok }
                        Label { text: "OK 正常"; color: Theme.ok; font.pixelSize: Theme.fontCaption }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.danger }
                        Label { text: "NG 异常"; color: Theme.danger; font.pixelSize: Theme.fontCaption }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.muted }
                        Label { text: "无记录"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                    }
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: "架轮立体示意图"
                    variant: "secondary"
                    Layout.preferredHeight: 30
                    onClicked: rackWheelDiagram.open()
                }

                Rectangle {
                    Layout.preferredHeight: 24
                    implicitWidth: updateLabel.implicitWidth + 16
                    radius: Theme.radiusPill
                    color: Theme.surfaceAlt
                    border.color: Theme.borderMuted
                    border.width: 1

                    Label {
                        id: updateLabel
                        anchors.centerIn: parent
                        text: lastUpdated === "" ? "数据加载中..." : "同步时间: " + lastUpdated
                        color: Theme.textSoft
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }

            // 16 轮位 × 50 架 全景遥测热力矩阵视窗（转置：纵向为16轮位+采集总计，横向为50架号，自适应铺满无滚动条）
            Rectangle {
                id: tableViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.fieldFill
                radius: Theme.radiusSmall
                border.width: 1
                border.color: Theme.borderMuted
                clip: true

                Item {
                    id: tableContainer
                    anchors.fill: parent
                    anchors.margins: 1

                    readonly property real wheelHeaderWidth: Math.max(112, Math.min(132, Math.floor(width * 0.08)))
                    readonly property real headerHeight: Math.max(26, Math.min(30, Math.floor(height * 0.045)))
                    readonly property int totalBodyRows: root.wheelRows.length + 1 // 16 轮位 + 1 采集总计 = 17 行
                    readonly property real rowHeight: (height - headerHeight) / totalBodyRows
                    readonly property real colWidth: (width - wheelHeaderWidth) / 50

                    // 顶端固定表头：轮位 / 架号 + 50 架号列 (1 ~ 50)
                    Rectangle {
                        id: pinnedHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: tableContainer.headerHeight
                        color: Theme.pressed
                        border.color: Theme.borderMuted
                        border.width: 1
                        z: 10

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            // 左上角：轮位 / 架号
                            Rectangle {
                                width: tableContainer.wheelHeaderWidth
                                height: parent.height
                                color: Theme.pressed
                                border.color: Theme.borderMuted
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "轮位 / 架号"
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.weight: Theme.fontMedium
                                    font.pixelSize: Theme.fontCaption
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onDoubleClicked: rackWheelDiagram.open()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "双击打开 3D 架轮立体示意图"
                                }
                            }

                            // 50 架列头 (1 ~ 50)
                            Repeater {
                                model: 50
                                delegate: Rectangle {
                                    id: rackHeaderCol
                                    required property int index
                                    readonly property int rackNumber: index + 1
                                    readonly property bool isColHovered: rackNumber === root.hoveredRack

                                    width: tableContainer.colWidth
                                    height: parent.height
                                    color: isColHovered ? Theme.pressed : (index % 2 === 0 ? Theme.surfaceAlt : Theme.surface)
                                    border.color: isColHovered ? Theme.borderStrong : Theme.borderMuted
                                    border.width: isColHovered ? 2 : 1
                                    z: isColHovered ? 2 : 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: rackHeaderCol.rackNumber
                                        color: rackHeaderCol.isColHovered ? Theme.text : Theme.textSoft
                                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                        font.weight: (rackHeaderCol.isColHovered) ? Theme.fontMedium : Theme.fontRegular
                                        font.pixelSize: Math.max(9, Math.min(Theme.fontCaption, Math.floor(tableContainer.colWidth * 0.38)))
                                    }

                                    ToolTip.visible: colHeaderMouse.containsMouse
                                    ToolTip.text: "架号 #" + rackHeaderCol.rackNumber
                                                  + "\n拍照采集总数: " + (root.photoCountByRack[rackHeaderCol.rackNumber] || 0)

                                    MouseArea {
                                        id: colHeaderMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.hoveredRack = rackHeaderCol.rackNumber
                                        onExited: {
                                            if (root.hoveredRack === rackHeaderCol.rackNumber)
                                                root.hoveredRack = -1
                                        }
                                        onDoubleClicked: rackWheelDiagram.open()
                                    }
                                }
                            }
                        }
                    }

                    // 16 轮位行 + 1 采集总计行视窗（完整铺满，无需滚动条）
                    Item {
                        id: bodyContainer
                        anchors.top: pinnedHeader.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true

                        Column {
                            anchors.fill: parent
                            spacing: 0

                            // 16 个轮位数据行
                            Repeater {
                                model: root.wheelRows
                                delegate: Rectangle {
                                    id: wheelRowItem
                                    required property var modelData
                                    required property int index
                                    readonly property int wheelNumber: modelData.wheel
                                    readonly property string wheelLabel: modelData.label
                                    readonly property bool isDrive: modelData.isDrive
                                    readonly property bool isRowHovered: wheelNumber === root.hoveredWheel

                                    width: bodyContainer.width
                                    height: tableContainer.rowHeight
                                    color: isRowHovered ? Theme.pressed : (index % 2 === 0 ? "transparent" : Theme.subtleFill)

                                    Row {
                                        anchors.fill: parent
                                        spacing: 0

                                        // 左侧：轮位行头
                                        Rectangle {
                                            id: wheelRowHeader
                                            width: tableContainer.wheelHeaderWidth
                                            height: parent.height
                                            color: wheelRowItem.isRowHovered
                                                ? Theme.pressed
                                                : (wheelRowItem.isDrive ? Theme.driveWheelSoft : Theme.walkWheelSoft)
                                            border.color: wheelRowItem.isRowHovered ? Theme.borderStrong : Theme.borderMuted
                                            border.width: wheelRowItem.isRowHovered ? 2 : 1
                                            z: wheelRowItem.isRowHovered ? 2 : 0

                                            // 左侧轮系类别色彩指示条
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: 3
                                                color: wheelRowItem.isDrive ? Theme.driveWheel : Theme.walkWheel
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 2
                                                text: wheelRowItem.wheelLabel.replace("/", "\n")
                                                horizontalAlignment: Text.AlignHCenter
                                                color: wheelRowItem.isRowHovered
                                                    ? Theme.accent
                                                    : (wheelRowItem.isDrive ? Theme.driveWheel : Theme.walkWheel)
                                                font.family: Theme.fontSans
                                                font.weight: Theme.fontMedium
                                                font.pixelSize: Theme.fontCaption
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: root.hoveredWheel = wheelRowItem.wheelNumber
                                                onExited: {
                                                    if (root.hoveredWheel === wheelRowItem.wheelNumber)
                                                        root.hoveredWheel = -1
                                                }
                                                onDoubleClicked: rackWheelDiagram.open()
                                            }
                                        }

                                        // 50 个架号状态单元格
                                        Repeater {
                                            model: 50
                                            delegate: Rectangle {
                                                id: cellRect
                                                required property int index
                                                readonly property int rackNumber: index + 1
                                                readonly property int wheelNumber: wheelRowItem.wheelNumber
                                                readonly property string wheelLabel: wheelRowItem.wheelLabel
                                                readonly property var cellState: root.statusByCell[root.cellKey(rackNumber, wheelNumber)]
                                                readonly property bool isCellHovered: rackNumber === root.hoveredRack && wheelNumber === root.hoveredWheel
                                                readonly property bool isCrosshair: (rackNumber === root.hoveredRack || wheelNumber === root.hoveredWheel) && !isCellHovered

                                                width: tableContainer.colWidth
                                                height: parent.height
                                                color: isCellHovered
                                                    ? Theme.pressed
                                                    : (!cellState
                                                        ? (isCrosshair ? Theme.surfaceAlt : "transparent")
                                                        : (cellState.result === 1 ? Theme.okSoft : Theme.dangerSoft))

                                                border.color: isCellHovered
                                                    ? Theme.accent
                                                    : (isCrosshair ? Theme.borderStrong : Theme.borderMuted)
                                                border.width: isCellHovered ? 2 : 1
                                                z: isCellHovered ? 3 : (isCrosshair ? 1 : 0)

                                                // 状态微晶指示点
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: isCellHovered ? 9 : 7
                                                    height: isCellHovered ? 9 : 7
                                                    radius: width / 2
                                                    visible: cellRect.cellState !== undefined
                                                    color: cellRect.cellState && cellRect.cellState.result === 1 ? Theme.ok : Theme.danger
                                                    border.width: 1
                                                    border.color: cellRect.cellState && cellRect.cellState.result === 1 ? Theme.okBorder : Theme.dangerBorder

                                                    Behavior on width { NumberAnimation { duration: Theme.animFast } }
                                                    Behavior on height { NumberAnimation { duration: Theme.animFast } }

                                                    SequentialAnimation on opacity {
                                                        loops: Animation.Infinite
                                                        running: cellRect.cellState ? (cellRect.cellState.result === 0) : false
                                                        NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
                                                        NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                                                    }
                                                }

                                                ToolTip.visible: cellMouse.containsMouse && Boolean(cellRect.cellState)
                                                ToolTip.text: cellRect.cellState
                                                              ? ("架号: #" + cellRect.rackNumber
                                                                    + " ╎ " + cellRect.wheelLabel
                                                                    + "\n判定: " + (cellRect.cellState.result === 1 ? "OK 正常" : "NG 异常")
                                                                    + "\n检测时间: " + cellRect.cellState.time
                                                                    + "\n单击直接查看检测原图")
                                                              : "暂无检测记录"

                                                MouseArea {
                                                    id: cellMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: cellRect.cellState ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onEntered: {
                                                        root.hoveredRack = cellRect.rackNumber
                                                        root.hoveredWheel = cellRect.wheelNumber
                                                    }
                                                    onExited: {
                                                        if (root.hoveredRack === cellRect.rackNumber) root.hoveredRack = -1
                                                        if (root.hoveredWheel === cellRect.wheelNumber) root.hoveredWheel = -1
                                                    }
                                                    onClicked: {
                                                        if (cellRect.cellState) {
                                                            var actualWheel = cellRect.cellState.wheel !== undefined ? cellRect.cellState.wheel : cellRect.wheelNumber
                                                            root.openLatestImage(cellRect.rackNumber, actualWheel, cellRect.wheelLabel)
                                                        }
                                                    }
                                                    onDoubleClicked: {
                                                        if (cellRect.cellState) {
                                                            var actualWheel = cellRect.cellState.wheel !== undefined ? cellRect.cellState.wheel : cellRect.wheelNumber
                                                            root.openLatestImage(cellRect.rackNumber, actualWheel, cellRect.wheelLabel)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 底部汇总行：各架拍照采集总数
                            Rectangle {
                                id: summaryRowItem
                                width: bodyContainer.width
                                height: tableContainer.rowHeight
                                color: Theme.pressed
                                border.color: Theme.borderMuted
                                border.width: 1

                                Row {
                                    anchors.fill: parent
                                    spacing: 0

                                    // 左侧表头：采集总计
                                    Rectangle {
                                        width: tableContainer.wheelHeaderWidth
                                        height: parent.height
                                        color: Theme.pressed
                                        border.color: Theme.borderMuted
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "采集总计"
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.fontCaption
                                            font.weight: Theme.fontMedium
                                        }
                                    }

                                    // 50 架各架的采集总数
                                    Repeater {
                                        model: 50
                                        delegate: Rectangle {
                                            id: summaryCell
                                            required property int index
                                            readonly property int rackNumber: index + 1
                                            readonly property bool isColHovered: rackNumber === root.hoveredRack
                                            readonly property int count: root.photoCountByRack[rackNumber] || 0

                                            width: tableContainer.colWidth
                                            height: parent.height
                                            color: isColHovered ? Theme.surfaceAlt : Theme.surface
                                            border.color: isColHovered ? Theme.borderStrong : Theme.borderMuted
                                            border.width: isColHovered ? 2 : 1
                                            z: isColHovered ? 2 : 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: summaryCell.count
                                                color: summaryCell.count > 0 ? Theme.accent : Theme.muted
                                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                                font.pixelSize: Math.max(9, Math.min(Theme.fontCaption, Math.floor(tableContainer.colWidth * 0.38)))
                                                font.weight: (summaryCell.count > 0) ? Theme.fontMedium : Theme.fontRegular
                                            }

                                            ToolTip.visible: summaryCellMouse.containsMouse
                                            ToolTip.text: "架号 #" + summaryCell.rackNumber + " ╎ 累计采集照片: " + summaryCell.count + " 张"

                                            MouseArea {
                                                id: summaryCellMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: root.hoveredRack = summaryCell.rackNumber
                                                onExited: {
                                                    if (root.hoveredRack === summaryCell.rackNumber)
                                                        root.hoveredRack = -1
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
        }
    }

    ZoomOverlay {
        id: imagePreview
        anchors.fill: parent
    }

    Dialog {
        id: rackWheelDiagram
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Overlay.overlay ? Overlay.overlay.width * 0.92 : 1120, 1200)
        height: Math.min(Overlay.overlay ? Overlay.overlay.height * 0.90 : 720, 800)
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surfaceFloating
            border.width: 1
            border.color: Theme.border
        }

        header: Rectangle {
            height: 48
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 10

                Rectangle {
                    width: 4
                    height: 18
                    radius: 2
                    color: Theme.borderStrong
                }

                Label {
                    text: "Carrier 点检工位 3D 数字孪生与架轮立体几何视窗"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontBold
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // 精巧关闭按钮
                Rectangle {
                    width: 30
                    height: 30
                    radius: Theme.radiusMicro
                    color: closeBtnMouse.containsMouse ? Theme.pressed : "transparent"
                    border.width: 1
                    border.color: closeBtnMouse.containsMouse ? Theme.border : "transparent"
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_close"
                        size: 16
                        color: closeBtnMouse.containsMouse ? Theme.text : Theme.textSoft
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rackWheelDiagram.close()
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.borderMuted
            }
        }

        contentItem: Rectangle {
            color: Theme.fieldFill
            radius: Theme.radiusSmall
            border.width: 1
            border.color: Theme.borderMuted
            clip: true

            DesignShow {
                anchors.fill: parent
                showHeader: false
                visible: rackWheelDiagram.visible
            }
        }
    }
}
