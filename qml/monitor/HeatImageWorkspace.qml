import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

// 热力图像：50 个架号最近一轮检测的 12 个相机图像，按架号分组浏览。
// 内存控制：列表只实例化可见的架号分组；图像经 image://thumb 按显示尺寸解码为缩略图，
// 由 C++ 侧有上限的缓存统一管理，界面不再保留原图；点击后才在查看器中加载原图。
Item {
    id: root
    anchors.fill: parent

    readonly property int rackCount: 50
    readonly property int cameraCount: 12

    property var rackGroups: []       // 下标 = 架号 - 1
    property var visibleRacks: []     // 当前筛选下显示的架号
    property string filterMode: "all" // all / ng / missing
    // 每个架号 2 行 × 6 列
    readonly property int tileColumns: 6
    readonly property int tileRows: 2
    property int roundRequestId: -1
    property bool loading: false
    property string lastUpdated: ""
    property int currentRack: 1

    readonly property int recordedRackCount: countRacks(function (g) { return g.cameraCount > 0 })
    readonly property int ngRackCount: countRacks(function (g) { return g.status === "ng" })
    readonly property int missingRackCount: countRacks(isMissing)
    readonly property int imageTotal: {
        var total = 0
        for (var i = 0; i < rackGroups.length; ++i)
            total += rackGroups[i].imageCount
        return total
    }

    function countRacks(predicate) {
        var count = 0
        for (var i = 0; i < rackGroups.length; ++i) {
            if (predicate(rackGroups[i]))
                ++count
        }
        return count
    }

    // 本轮有记录但图像不齐（未上报的相机或图片未到达）
    function isMissing(group) {
        return group.cameraCount > 0 && group.imageCount < root.cameraCount
    }

    function groupFor(rack) {
        return rack >= 1 && rack <= rackGroups.length ? rackGroups[rack - 1] : null
    }

    function refresh() {
        if (!appController || !appController.requestRoundImages)
            return
        loading = true
        roundRequestId = appController.requestRoundImages()
    }

    function rebuildVisible() {
        var racks = []
        for (var i = 0; i < rackGroups.length; ++i) {
            var group = rackGroups[i]
            if (filterMode === "ng" && group.status !== "ng")
                continue
            if (filterMode === "missing" && !isMissing(group))
                continue
            racks.push(group.rack)
        }
        visibleRacks = racks
    }

    function setFilter(mode) {
        if (filterMode === mode)
            return
        filterMode = mode
        rebuildVisible()
        rackList.positionViewAtBeginning()
    }

    function scrollToRack(rack) {
        var index = visibleRacks.indexOf(rack)
        if (index < 0) {
            // 目标架号被当前筛选隐藏：切回全部再定位
            filterMode = "all"
            rebuildVisible()
            index = visibleRacks.indexOf(rack)
        }
        if (index >= 0) {
            rackList.positionViewAtIndex(index, ListView.Beginning)
            currentRack = rack
        }
    }

    function updateCurrentRack() {
        var index = rackList.indexAt(Theme.space4, rackList.contentY + Theme.space4)
        if (index >= 0 && index < visibleRacks.length)
            currentRack = visibleRacks[index]
    }

    function thumbSource(path) {
        return path && path.length > 0 ? "image://thumb/" + encodeURIComponent(path) : ""
    }

    function cameraLabel(cameraId) {
        return "CAM " + (cameraId < 10 ? "0" : "") + cameraId
    }

    function wheelLabels(image) {
        var labels = []
        var wheelIds = image && image.wheelIds ? image.wheelIds : []
        for (var i = 0; i < wheelIds.length; ++i) {
            var label = appController.wheelLabel(wheelIds[i])
            if (labels.indexOf(label) < 0)
                labels.push(label)
        }
        return labels.join("\n")
    }

    function openImage(rack, image) {
        if (!image || !image.hasImage)
            return
        var detail = (image.result === 1 ? "OK 正常" : "NG 异常") + " · 采集时间: " + image.time
        if (image.wheels && image.wheels.length > 0)
            detail += " · " + image.wheels.join(" · ")
        imagePreview.openViewer(image.fileUrl, "架号 #" + rack + " · " + cameraLabel(image.cameraId), detail)
    }

    Component.onCompleted: refresh()

    Connections {
        target: appController
        function onRoundImagesReady(requestId, racks) {
            if (requestId !== root.roundRequestId)
                return
            root.loading = false
            root.rackGroups = racks || []
            root.rebuildVisible()
            root.lastUpdated = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
        }
        function onRecordImagesChanged() {
            // 一个载具两次触发、图片与记录先后到达，合并短时间内的多次变化后再刷新
            refreshTimer.restart()
        }
    }

    Timer {
        id: refreshTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
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

            // 标题、汇总与操作
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Rectangle {
                    width: 4
                    height: 18
                    radius: Theme.radiusPill
                    color: Theme.borderStrong
                }

                Label {
                    text: "本轮图像总览"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontMedium
                }

                Label {
                    Layout.leftMargin: Theme.space2
                    text: "有记录 " + root.recordedRackCount + " / " + root.rackCount + " 架 · NG "
                          + root.ngRackCount + " 架 · 图像 " + root.imageTotal + " 张"
                    color: Theme.textSoft
                    font.family: Theme.fontSans
                    font.features: Theme.fontFeaturesTabular
                    font.pixelSize: Theme.fontCaption
                }

                Item { Layout.fillWidth: true }

                // 筛选：全部 / NG 架 / 缺图架
                Rectangle {
                    Layout.preferredHeight: 30
                    implicitWidth: filterRow.implicitWidth + 4
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.borderMuted

                    Row {
                        id: filterRow
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: [
                                { mode: "all", label: "全部" },
                                { mode: "ng", label: "NG 架" },
                                { mode: "missing", label: "缺图架" }
                            ]
                            delegate: Rectangle {
                                id: filterItem
                                required property var modelData
                                readonly property bool selected: root.filterMode === modelData.mode
                                readonly property int badge: modelData.mode === "ng" ? root.ngRackCount
                                                           : (modelData.mode === "missing" ? root.missingRackCount : root.rackCount)

                                width: filterLabel.implicitWidth + Theme.space4
                                height: 26
                                radius: Theme.radiusMicro
                                color: selected ? Theme.surface : (filterMouse.containsMouse ? Theme.hover : "transparent")
                                border.width: selected ? 1 : 0
                                border.color: Theme.selectedBorder

                                Label {
                                    id: filterLabel
                                    anchors.centerIn: parent
                                    text: filterItem.modelData.label + " " + filterItem.badge
                                    color: filterItem.selected ? Theme.accent : Theme.textSoft
                                    font.family: Theme.fontSans
                                    font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: filterItem.selected ? Theme.fontMedium : Theme.fontRegular
                                }

                                MouseArea {
                                    id: filterMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setFilter(filterItem.modelData.mode)
                                }
                            }
                        }
                    }
                }

                ActionButton {
                    text: root.loading ? "刷新中..." : "刷新"
                    variant: "secondary"
                    enabled: !root.loading
                    Layout.preferredHeight: 30
                    onClicked: root.refresh()
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
                        text: root.lastUpdated === "" ? "数据加载中..." : "同步时间: " + root.lastUpdated
                        color: Theme.textSoft
                        font.family: Theme.fontSans
                        font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }

            // 架号索引：颜色表示本轮判定，点击跳转到该架
            Item {
                id: rackIndex
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                readonly property real chipSpacing: 2
                readonly property real chipWidth: (width - chipSpacing * (root.rackCount - 1)) / root.rackCount

                Row {
                    anchors.fill: parent
                    spacing: rackIndex.chipSpacing

                    Repeater {
                        model: root.rackCount
                        delegate: Rectangle {
                            id: chip
                            required property int index
                            readonly property int rack: index + 1
                            readonly property var group: root.groupFor(rack)
                            readonly property string status: group ? group.status : "none"
                            readonly property bool isCurrent: root.currentRack === rack
                            readonly property bool hidden: root.visibleRacks.indexOf(rack) < 0

                            width: rackIndex.chipWidth
                            height: parent.height
                            radius: Theme.radiusMicro
                            opacity: hidden ? 0.4 : 1.0
                            color: chipMouse.containsMouse ? Theme.pressed
                                 : (status === "ng" ? Theme.dangerSoft : (status === "ok" ? Theme.okSoft : Theme.surfaceAlt))
                            border.width: isCurrent ? 2 : 1
                            border.color: isCurrent ? Theme.selectedBorder
                                        : (chipMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted)

                            Text {
                                anchors.centerIn: parent
                                text: chip.rack
                                color: chip.status === "ng" ? Theme.danger
                                     : (chip.status === "ok" ? Theme.ok : Theme.disabled)
                                font.family: Theme.fontSans
                                font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontMicro
                                font.weight: chip.isCurrent ? Theme.fontMedium : Theme.fontRegular
                            }

                            ToolTip.visible: chipMouse.containsMouse
                            ToolTip.delay: 300
                            ToolTip.text: !chip.group || chip.group.cameraCount === 0
                                          ? "架号 #" + chip.rack + "：暂无检测记录"
                                          : "架号 #" + chip.rack + " · " + chip.group.time
                                            + "\n图像 " + chip.group.imageCount + " / " + root.cameraCount
                                            + " · NG 相机 " + chip.group.ngCount

                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.scrollToRack(chip.rack)
                            }
                        }
                    }
                }
            }

            // 分组图像列表：只实例化视野内（及上下少量预加载）的架号分组
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.window
                radius: Theme.radiusSmall
                clip: true

                ListView {
                    id: rackList
                    anchors.fill: parent
                    anchors.margins: Theme.space2
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space3
                    model: root.visibleRacks
                    cacheBuffer: Math.max(0, Math.round(height / 2))
                    boundsBehavior: Flickable.StopAtBounds
                    onContentYChanged: root.updateCurrentRack()

                    ScrollBar.vertical: ScrollBar {
                        parent: rackList.parent
                        anchors.top: rackList.top
                        anchors.bottom: rackList.bottom
                        anchors.left: rackList.right
                        anchors.leftMargin: 1
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: rackGroup
                        required property var modelData
                        readonly property int rack: modelData
                        readonly property var group: root.groupFor(rack)
                        // 图块保持 4:3；按宽度铺满，但高度不超过列表可视区，保证一个架号的 12 幅图完整显示在一屏内
                        readonly property real widthLimitedTile: (width - Theme.space3 * 2
                                                                  - grid.columnSpacing * (root.tileColumns - 1)) / root.tileColumns
                        readonly property real heightLimitedTile: (rackList.height - groupHeader.height - Theme.space3 * 2 - Theme.space2
                                                                   - grid.rowSpacing * (root.tileRows - 1)) / root.tileRows
                        readonly property real tileHeight: Math.floor(Math.max(90, Math.min(widthLimitedTile * 3 / 4, heightLimitedTile)))
                        readonly property real tileWidth: Math.floor(tileHeight * 4 / 3)

                        width: rackList.width
                        height: groupHeader.height + grid.height + Theme.space3 * 2 + Theme.space2
                        radius: Theme.radiusMedium
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.borderMuted

                        RowLayout {
                            id: groupHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: Theme.space3
                            anchors.leftMargin: Theme.space3
                            anchors.rightMargin: Theme.space3
                            height: 24
                            spacing: Theme.space2

                            Label {
                                text: "架号 #" + rackGroup.rack
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontMedium
                            }

                            Rectangle {
                                readonly property string status: rackGroup.group ? rackGroup.group.status : "none"
                                Layout.preferredHeight: 20
                                implicitWidth: statusLabel.implicitWidth + Theme.space3
                                radius: Theme.radiusPill
                                color: status === "ng" ? Theme.dangerSoft : (status === "ok" ? Theme.okSoft : Theme.surfaceAlt)
                                border.width: 1
                                border.color: status === "ng" ? Theme.dangerBorder : (status === "ok" ? Theme.okBorder : Theme.borderMuted)

                                Label {
                                    id: statusLabel
                                    anchors.centerIn: parent
                                    text: parent.status === "ng" ? "NG " + rackGroup.group.ngCount + " 相机"
                                        : (parent.status === "ok" ? "全部 OK" : "暂无记录")
                                    color: parent.status === "ng" ? Theme.danger : (parent.status === "ok" ? Theme.ok : Theme.muted)
                                    font.family: Theme.fontSans
                                    font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.fontMedium
                                }
                            }

                            Label {
                                visible: rackGroup.group && rackGroup.group.cameraCount > 0
                                text: rackGroup.group ? "本轮时间 " + rackGroup.group.time : ""
                                color: Theme.muted
                                font.family: Theme.fontSans
                                font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                            }

                            Item { Layout.fillWidth: true }

                            Label {
                                visible: rackGroup.group && rackGroup.group.cameraCount > 0
                                text: rackGroup.group ? "图像 " + rackGroup.group.imageCount + " / " + root.cameraCount : ""
                                color: rackGroup.group && rackGroup.group.imageCount < root.cameraCount ? Theme.warn : Theme.textSoft
                                font.family: Theme.fontSans
                                font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        Grid {
                            id: grid
                            anchors.top: groupHeader.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: Theme.space2
                            columns: root.tileColumns
                            columnSpacing: Theme.space2
                            rowSpacing: Theme.space2

                            Repeater {
                                model: root.cameraCount
                                delegate: Rectangle {
                                    id: tile
                                    required property int index
                                    readonly property var image: rackGroup.group ? rackGroup.group.images[index] : null
                                    readonly property bool hasRecord: Boolean(image && image.hasRecord)
                                    readonly property bool hasImage: Boolean(image && image.hasImage)
                                    readonly property bool isNg: hasRecord && image.result === 0

                                    width: rackGroup.tileWidth
                                    height: rackGroup.tileHeight
                                    radius: Theme.radiusSmall
                                    color: hasImage && thumb.status !== Image.Error ? Theme.imageStage : Theme.surfaceAlt
                                    border.width: isNg ? 2 : 1
                                    border.color: isNg ? Theme.danger
                                                : (tileMouse.containsMouse && hasImage ? Theme.borderStrong : Theme.borderMuted)
                                    clip: true

                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        anchors.margins: tile.border.width
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        // 缩略图由 C++ 缓存管理，避免 QML 图片缓存再保留一份
                                        cache: false
                                        smooth: true
                                        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                                            Math.ceil(height * Screen.devicePixelRatio))
                                        source: tile.hasImage ? root.thumbSource(tile.image.filePath) : ""
                                        opacity: status === Image.Ready ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                                    }

                                    // 无图、解码失败占位
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Theme.space1
                                        visible: !tile.hasImage || thumb.status === Image.Error

                                        AppIcon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            name: "icon_image"
                                            size: 20
                                            color: Theme.muted
                                            opacity: 0.5
                                        }

                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: !tile.hasRecord ? "本轮未上报"
                                                : (!tile.hasImage ? "图像未到达" : "无法预览")
                                            color: Theme.muted
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.fontCaption
                                        }
                                    }

                                    // 左上角显示该图像关联的轮位，多轮共图时逐行显示
                                    Rectangle {
                                        visible: wheelLabel.text.length > 0
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: Theme.space1
                                        height: wheelLabel.implicitHeight + Theme.space1
                                        width: Math.min(wheelLabel.implicitWidth + Theme.space2,
                                                        parent.width - Theme.space1 * 3
                                                        - (tile.hasRecord ? resultBadge.width : 0))
                                        radius: Theme.radiusMicro
                                        color: Theme.overlayFill

                                        Text {
                                            id: wheelLabel
                                            anchors.centerIn: parent
                                            width: parent.width - Theme.space2
                                            text: root.wheelLabels(tile.image)
                                            wrapMode: Text.Wrap
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.features: Theme.fontFeaturesTabular
                                            font.pixelSize: Theme.fontCaption
                                            font.weight: Theme.fontMedium
                                        }
                                    }

                                    // 右上角判定
                                    Rectangle {
                                        id: resultBadge
                                        visible: tile.hasRecord
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: Theme.space1
                                        height: 18
                                        width: resultLabel.implicitWidth + Theme.space2
                                        radius: Theme.radiusMicro
                                        color: tile.isNg ? Theme.danger : Theme.overlayFill

                                        Text {
                                            id: resultLabel
                                            anchors.centerIn: parent
                                            text: tile.isNg ? "NG" : "OK"
                                            color: tile.isNg ? Theme.textOnAccent : Theme.ok
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.fontMicro
                                            font.weight: Theme.fontMedium
                                        }
                                    }

                                    ToolTip.visible: tileMouse.containsMouse && tile.hasRecord
                                    ToolTip.delay: 400
                                    ToolTip.text: tile.hasRecord
                                                  ? (tile.image.fileName + "\n" + tile.image.time
                                                     + (tile.image.wheels.length > 0 ? "\n" + tile.image.wheels.join("\n") : "")
                                                     + (tile.hasImage ? "\n单击查看原图" : ""))
                                                  : ""

                                    MouseArea {
                                        id: tileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: tile.hasImage ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.openImage(rackGroup.rack, tile.image)
                                    }
                                }
                            }
                        }
                    }
                }

                // 空状态
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    visible: !root.loading && root.visibleRacks.length === 0

                    AppIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "icon_image"
                        size: 32
                        color: Theme.muted
                        opacity: 0.5
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.filterMode === "ng" ? "本轮没有 NG 的架号"
                            : (root.filterMode === "missing" ? "本轮各架图像均已齐全" : "暂无检测记录")
                        color: Theme.muted
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontBody
                    }
                }
            }
        }
    }

    ZoomOverlay {
        id: imagePreview
        anchors.fill: parent
    }
}
