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

    function refreshStatus() {
        if (!appController || !appController.rackWheelMonitorStatus)
            return

        var latest = appController.rackWheelMonitorStatus()
        var cells = ({})
        for (var i = 0; i < latest.length; ++i) {
            var item = latest[i]
            cells[cellKey(item.rack, item.wheel)] = item
        }
        statusByCell = cells

        var photoCounts = appController.rackPhotoCounts ? appController.rackPhotoCounts() : []
        var counts = ({})
        for (var j = 0; j < photoCounts.length; ++j)
            counts[photoCounts[j].rack] = Number(photoCounts[j].count) || 0
        photoCountByRack = counts
        lastUpdated = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
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

    readonly property var wheelRows: [
        { label: "驱动 1", wheel: 1, isDrive: true }, { label: "驱动 2", wheel: 2, isDrive: true },
        { label: "驱动 3", wheel: 3, isDrive: true }, { label: "驱动 4", wheel: 4, isDrive: true },
        { label: "驱动 5", wheel: 5, isDrive: true }, { label: "驱动 6", wheel: 6, isDrive: true },
        { label: "驱动 7", wheel: 7, isDrive: true }, { label: "驱动 8", wheel: 8, isDrive: true },
        { label: "走行 9", wheel: 9, isDrive: false }, { label: "走行 10", wheel: 10, isDrive: false },
        { label: "走行 11", wheel: 11, isDrive: false }, { label: "走行 12", wheel: 12, isDrive: false },
        { label: "走行 13", wheel: 13, isDrive: false }, { label: "走行 14", wheel: 14, isDrive: false },
        { label: "走行 15", wheel: 15, isDrive: false }, { label: "走行 16", wheel: 16, isDrive: false }
    ]
    readonly property var wheelColumns: wheelRows

    Component.onCompleted: refreshStatus()

    Connections {
        target: appController
        function onRackWheelMonitorUpdated() {
            root.refreshStatus()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.bgCard
        border.width: 1
        border.color: Theme.borderMedium

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
                    color: Theme.primary
                }

                Label {
                    text: "16 轮位 × 50 架 全景遥测热力矩阵"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeH2
                    font.bold: true
                }

                // 状态图例
                RowLayout {
                    Layout.leftMargin: 12
                    spacing: 12

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.ok }
                        Label { text: "OK 正常"; color: Theme.okLight; font.pixelSize: Theme.fontSizeSmall }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.ng }
                        Label { text: "NG 异常"; color: Theme.ngLight; font.pixelSize: Theme.fontSizeSmall }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle { width: 8; height: 8; radius: 4; color: Theme.textMuted }
                        Label { text: "无记录"; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
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
                    color: Theme.bgCardElevated
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Label {
                        id: updateLabel
                        anchors.centerIn: parent
                        text: lastUpdated === "" ? "数据加载中..." : "同步时间: " + lastUpdated
                        color: Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // 16 轮位 × 50 架 全景遥测热力矩阵视窗（转置：纵向为16轮位+采集总计，横向为50架号，自适应铺满无滚动条）
            Rectangle {
                id: tableViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgInput
                radius: Theme.radiusMd
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                Item {
                    id: tableContainer
                    anchors.fill: parent
                    anchors.margins: 1

                    readonly property real wheelHeaderWidth: Math.max(76, Math.min(92, Math.floor(width * 0.055)))
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
                        color: Theme.bgCardActive
                        border.color: Theme.borderSubtle
                        border.width: 1
                        z: 10

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            // 左上角：轮位 / 架号
                            Rectangle {
                                width: tableContainer.wheelHeaderWidth
                                height: parent.height
                                color: Theme.bgCardActive
                                border.color: Theme.borderSubtle
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "轮位 / 架号"
                                    color: Theme.primaryLight
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeSmall
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
                                    color: isColHovered ? Theme.bgCardActive : (index % 2 === 0 ? Theme.bgCardElevated : Theme.bgCard)
                                    border.color: isColHovered ? Theme.primary : Theme.borderSubtle
                                    border.width: isColHovered ? 2 : 1
                                    z: isColHovered ? 2 : 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: rackHeaderCol.rackNumber
                                        color: rackHeaderCol.isColHovered ? Theme.primaryLight : Theme.textSecondary
                                        font.family: Theme.fontMono
                                        font.bold: rackHeaderCol.isColHovered
                                        font.pixelSize: Math.max(9, Math.min(Theme.fontSizeSmall, Math.floor(tableContainer.colWidth * 0.38)))
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
                                    color: isRowHovered ? Theme.bgCardActive : (index % 2 === 0 ? "transparent" : (Theme.isDark ? "#06ffffff" : "#04000000"))

                                    Row {
                                        anchors.fill: parent
                                        spacing: 0

                                        // 左侧：轮位行头
                                        Rectangle {
                                            id: wheelRowHeader
                                            width: tableContainer.wheelHeaderWidth
                                            height: parent.height
                                            color: wheelRowItem.isRowHovered
                                                ? Theme.bgCardActive
                                                : (wheelRowItem.isDrive ? Theme.driveWheelBg : Theme.walkWheelBg)
                                            border.color: wheelRowItem.isRowHovered ? Theme.primary : Theme.borderSubtle
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
                                                text: wheelRowItem.wheelLabel
                                                color: wheelRowItem.isRowHovered
                                                    ? Theme.primaryLight
                                                    : (wheelRowItem.isDrive ? Theme.driveWheel : Theme.walkWheel)
                                                font.family: Theme.fontFamily
                                                font.bold: true
                                                font.pixelSize: Theme.fontSizeSmall
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
                                                    ? Theme.bgCardActive
                                                    : (!cellState
                                                        ? (isCrosshair ? Theme.bgCardElevated : "transparent")
                                                        : (cellState.result === 1 ? Theme.okBg : Theme.ngBg))

                                                border.color: isCellHovered
                                                    ? Theme.primary
                                                    : (isCrosshair ? Theme.borderHover : Theme.borderSubtle)
                                                border.width: isCellHovered ? 2 : 1
                                                z: isCellHovered ? 3 : (isCrosshair ? 1 : 0)

                                                // 状态微晶指示点
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: isCellHovered ? 9 : 7
                                                    height: isCellHovered ? 9 : 7
                                                    radius: width / 2
                                                    visible: cellRect.cellState !== undefined
                                                    color: cellRect.cellState && cellRect.cellState.result === 1 ? Theme.ok : Theme.ng
                                                    border.width: 1
                                                    border.color: cellRect.cellState && cellRect.cellState.result === 1 ? Theme.okBorder : Theme.ngBorder

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
                                                                    + "\n💡 单击直接查看检测原图")
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
                                color: Theme.bgCardActive
                                border.color: Theme.borderSubtle
                                border.width: 1

                                Row {
                                    anchors.fill: parent
                                    spacing: 0

                                    // 左侧表头：采集总计
                                    Rectangle {
                                        width: tableContainer.wheelHeaderWidth
                                        height: parent.height
                                        color: Theme.bgCardActive
                                        border.color: Theme.borderSubtle
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "采集总计"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
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
                                            color: isColHovered ? Theme.bgCardElevated : Theme.bgCard
                                            border.color: isColHovered ? Theme.primary : Theme.borderSubtle
                                            border.width: isColHovered ? 2 : 1
                                            z: isColHovered ? 2 : 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: summaryCell.count
                                                color: summaryCell.count > 0 ? Theme.primaryLight : Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: Math.max(9, Math.min(Theme.fontSizeSmall, Math.floor(tableContainer.colWidth * 0.38)))
                                                font.bold: summaryCell.count > 0
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
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
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
                    color: Theme.primary
                }

                Label {
                    text: "Carrier 点检工位 3D 数字孪生与架轮立体几何视窗"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontH2
                    font.weight: Theme.weightBold
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // 精巧关闭按钮
                Rectangle {
                    width: 30
                    height: 30
                    radius: Theme.radiusSm
                    color: closeBtnMouse.containsMouse ? Theme.bgCardActive : "transparent"
                    border.width: 1
                    border.color: closeBtnMouse.containsMouse ? Theme.borderMedium : "transparent"
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 13
                        color: closeBtnMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
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
                color: Theme.borderSubtle
            }
        }

        contentItem: Rectangle {
            color: Theme.bgInput
            radius: Theme.radiusMd
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

            DesignShow {
                anchors.fill: parent
                showHeader: false
                visible: rackWheelDiagram.visible
            }
        }
    }
}
