import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle {
        color: "transparent"
    }

    // 0: 3D数字孪生视窗, 1: 实时点检批次
    property int currentLeftCardView: 0

    property string batchSummaryText: ((typeof appController !== 'undefined' && appController && appController.currentSerialsRaw && appController.currentSerialsRaw.length > 0) ? ("当前序列号: " + appController.currentSerialsRaw) : "等待点检数据...")

    property var detectionOverview: ({})
    readonly property int currentRack: detectionOverview.rack || 0
    readonly property var driveWheels: detectionOverview.drive || []
    readonly property var walkingWheels: detectionOverview.walking || []
    readonly property int currentRackNgCount: detectionOverview.ngCount || 0
    readonly property int currentRackTotalCount: detectionOverview.totalCount || 0
    readonly property real currentRackNgRate: detectionOverview.ngRate || 0

    readonly property var effectiveDriveWheels: {
        if (currentRack > 0 && driveWheels && driveWheels.length === 8) {
            return driveWheels;
        }
        var arr = [];
        for (var i = 1; i <= 8; i++) {
            arr.push({
                wheel: i,
                result: -1,
                time: "",
                passRate: 0.0
            });
        }
        return arr;
    }

    readonly property var effectiveWalkingWheels: {
        if (currentRack > 0 && walkingWheels && walkingWheels.length === 8) {
            return walkingWheels;
        }
        var arr2 = [];
        for (var j = 9; j <= 16; j++) {
            arr2.push({
                wheel: j,
                result: -1,
                time: "",
                passRate: 0.0
            });
        }
        return arr2;
    }

    // 当前选中的轮号 (1~8 驱动轮, 9~16 走行轮, 0 未选中)
    property int selectedWheel: 0

    // 将轮号转换为 3D 标签名称
    function wheelToTagName(wheel) {
        return appController.wheelTagName(wheel);
    }

    // 将 3D 标签名称转换为轮号
    function tagNameToWheel(name) {
        return appController.wheelFromTagName(name || "");
    }

    // 选择轮位联动
    function selectWheel(wheel) {
        if (selectedWheel === wheel) {
            selectedWheel = 0;
            designShow.selectedTag = "";
        } else {
            selectedWheel = wheel;
            designShow.selectedTag = wheelToTagName(wheel);
        }
    }

    property int detectionRequestId: -1

    function refreshDetection() {
        if (appController && appController.requestStats)
            detectionRequestId = appController.requestStats("homepageCurrentDetection", []);
    }

    function openLatestImage(wheel) {
        if (currentRack <= 0 || !appController || !appController.latestRackWheelMonitorImage)
            return;
        var image = appController.latestRackWheelMonitorImage(currentRack, wheel);
        if (!image.filePath || String(image.filePath).length === 0)
            return;
        var normalizedPath = String(image.filePath).replace(/\\/g, "/");
        var sourceUrl = /^[a-zA-Z]:\//.test(normalizedPath) ? "file:///" + normalizedPath : normalizedPath;
        var wheelName = appController.wheelLabel(wheel);
        imagePreview.openViewer(sourceUrl, "架号 " + currentRack + " · " + wheelName, "最新检测判定: " + (image.result === 1 ? "OK 正常" : "NG 异常") + " ╎ 采集时间: " + image.time);
    }

    Component.onCompleted: refreshDetection()

    Connections {
        target: appController

        function onRackWheelMonitorUpdated() {
            root.refreshDetection();
        }

        function onCurrentBatchChanged() {
            root.refreshDetection();
        }

        function onStatsReady(requestId, kind, result) {
            if (requestId === root.detectionRequestId)
                root.detectionOverview = result || ({});
        }
    }

    Component {
        id: wheelResultDelegate

        Rectangle {
            id: delegateRoot
            required property var modelData
            readonly property bool isOk: Boolean(modelData && (modelData.result === 1 || modelData.result === "1" || modelData.result === "OK" || modelData.result === "ok"))
            readonly property bool isNg: Boolean(modelData && (modelData.result === 0 || modelData.result === "0" || modelData.result === "NG" || modelData.result === "ng"))
            readonly property bool hasResult: isOk || isNg
            readonly property bool isSelected: Boolean(delegateRoot.modelData && (root.selectedWheel === delegateRoot.modelData.wheel))

            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 32
            radius: Theme.radiusMicro

            color: isSelected ? Theme.activeSubtle : (resultMouse.containsMouse ? Theme.hover : (!hasResult ? Theme.surface : (isOk ? Theme.okSoft : Theme.dangerSoft)))

            border.width: isSelected ? 1.5 : 1
            border.color: isSelected ? Theme.accent : (resultMouse.containsMouse ? Theme.borderStrong : (!hasResult ? Theme.borderMuted : (isOk ? Theme.okBorder : Theme.dangerBorder)))

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animFast
                }
            }
            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.animFast
                }
            }

            // 行点击与悬浮检测区域 (置于底层，不遮挡 eyeMouse)
            MouseArea {
                id: resultMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (delegateRoot.modelData && delegateRoot.modelData.wheel !== undefined) {
                        root.selectWheel(delegateRoot.modelData.wheel);
                    }
                }
            }

            // 选中指示光条
            Rectangle {
                width: 3
                height: 16
                radius: 1.5
                color: Theme.borderStrong
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                visible: delegateRoot.isSelected
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                // 状态脉冲指示灯
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: !delegateRoot.hasResult ? Theme.muted : (delegateRoot.isOk ? Theme.ok : Theme.danger)
                    Layout.alignment: Qt.AlignVCenter

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: delegateRoot.hasResult
                        NumberAnimation {
                            from: 1.0
                            to: 0.4
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: 0.4
                            to: 1.0
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                    }
                }

                Label {
                    text: {
                        return appController.wheelLabel(delegateRoot.modelData ? delegateRoot.modelData.wheel : 0);
                    }
                    color: delegateRoot.hasResult ? Theme.text : Theme.textSoft
                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                    font.pixelSize: Theme.fontCaption
                    font.weight: Theme.fontMedium
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                // 结果徽章 (当前判定 OK / NG 工业状态药丸)
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 20
                    radius: Theme.radiusMicro
                    color: !delegateRoot.hasResult ? Theme.surfaceAlt : (delegateRoot.isOk ? Theme.ok : Theme.danger)
                    border.width: 1
                    border.color: !delegateRoot.hasResult ? Theme.borderMuted : (delegateRoot.isOk ? Theme.okBorder : Theme.dangerBorder)
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        anchors.centerIn: parent
                        text: !delegateRoot.hasResult ? "--" : (delegateRoot.isOk ? "OK" : "NG")
                        color: !delegateRoot.hasResult ? Theme.muted : Theme.textOnAccent
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.fontBold
                    }
                }

                // 当日合格率微进度
                ColumnLayout {
                    Layout.preferredWidth: 54
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: (delegateRoot.hasResult && delegateRoot.modelData) ? (Number(delegateRoot.modelData.passRate || 0).toFixed(1) + "%") : "--"
                        color: delegateRoot.hasResult ? Theme.textSoft : Theme.muted
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.fontMedium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 3
                        radius: 1.5
                        color: Theme.surfaceAlt

                        Rectangle {
                            height: parent.height
                            radius: 1.5
                            width: (delegateRoot.hasResult && delegateRoot.modelData) ? (parent.width * Math.min(1.0, Math.max(0.0, (delegateRoot.modelData.passRate || 0) / 100))) : 0
                            color: delegateRoot.isOk ? Theme.ok : Theme.danger
                        }
                    }
                }

                // 查看原图快捷动作按钮
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: Theme.radiusMicro
                    color: (!delegateRoot.hasResult) ? Theme.surfaceAlt : (eyeMouse.containsMouse ? Theme.pressed : Theme.surfaceAlt)
                    border.width: 1
                    border.color: (!delegateRoot.hasResult) ? Theme.borderMuted : (eyeMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted)
                    opacity: delegateRoot.hasResult ? 1.0 : 0.35
                    Layout.alignment: Qt.AlignVCenter

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_eye"
                        size: 11
                        color: (!delegateRoot.hasResult) ? Theme.muted : (eyeMouse.containsMouse ? Theme.text : Theme.textSoft)
                    }

                    MouseArea {
                        id: eyeMouse
                        anchors.fill: parent
                        enabled: delegateRoot.hasResult
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (delegateRoot.modelData && delegateRoot.modelData.wheel !== undefined) {
                                root.selectWheel(delegateRoot.modelData.wheel);
                                root.openLatestImage(delegateRoot.modelData.wheel);
                            }
                        }
                    }

                    ToolTip.visible: eyeMouse.containsMouse && delegateRoot.hasResult
                    ToolTip.delay: 200
                    ToolTip.text: "轻触查看点检原图"
                }
            }

            ToolTip.visible: resultMouse.containsMouse && !eyeMouse.containsMouse
            ToolTip.text: "点击在3D模型中定位高亮标签" + (delegateRoot.hasResult ? ("\n检测时间：" + ((delegateRoot.modelData && delegateRoot.modelData.time) ? delegateRoot.modelData.time : "实时")) : "\n(暂无点检记录)")
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // ===== 左栏：3D数字孪生视窗 (3D Digital Twin HUD) =====
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: root.width * 0.52
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

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
                        text: root.currentLeftCardView === 0 ? "Carrier 机构数字孪生视窗" : "Carrier 实时点检工位图像"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontTitle
                        font.weight: Theme.fontMedium
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // 1. 3D 模式：实时架号状态指示胶囊
                    Rectangle {
                        Layout.preferredHeight: 28
                        implicitWidth: rackStatusRow.implicitWidth + 24
                        radius: Theme.radiusPill
                        color: currentRack > 0 ? Theme.pressed : Theme.surfaceAlt
                        border.color: currentRack > 0 ? Theme.accent : Theme.border
                        border.width: 1
                        visible: root.currentLeftCardView === 0

                        RowLayout {
                            id: rackStatusRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: currentRack > 0 ? Theme.ok : Theme.warn

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: 1.0
                                        to: 0.3
                                        duration: 800
                                        easing.type: Easing.InOutQuad
                                    }
                                    NumberAnimation {
                                        from: 0.3
                                        to: 1.0
                                        duration: 800
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }

                            Label {
                                text: currentRack > 0 ? "正在巡检架号 #" + currentRack : "就绪 · 实时点检工位"
                                color: currentRack > 0 ? Theme.text : Theme.textSoft
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                                font.weight: (currentRack > 0) ? Theme.fontMedium : Theme.fontRegular
                            }
                        }
                    }

                    // 2. 批次模式：序列号实时状态指示胶囊
                    Rectangle {
                        Layout.preferredHeight: 28
                        implicitWidth: batchSerialRow.implicitWidth + 20
                        radius: Theme.radiusPill
                        color: Theme.surfaceAlt
                        border.color: Theme.borderMuted
                        border.width: 1
                        visible: root.currentLeftCardView === 1

                        RowLayout {
                            id: batchSerialRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.accent
                            }

                            Text {
                                text: root.batchSummaryText
                                color: Theme.text
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                            }
                        }
                    }

                    // 3. 卡片右上角视图切换控制胶囊 (Segmented Toggle Control)
                    Rectangle {
                        id: viewSwitchContainer
                        Layout.preferredHeight: 30
                        implicitWidth: switchRow.implicitWidth + 8
                        radius: Theme.radiusPill
                        color: Theme.fieldFill
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            id: switchRow
                            anchors.centerIn: parent
                            spacing: 3

                            // 选项 1：数字孪生视图
                            Rectangle {
                                id: btn3D
                                Layout.preferredHeight: 24
                                implicitWidth: seg3DRow.implicitWidth + 18
                                radius: 12
                                color: root.currentLeftCardView === 0 ? Theme.accent : (mouse3D.containsMouse ? Theme.surfaceAlt : "transparent")
                                border.width: 1
                                border.color: root.currentLeftCardView === 0 ? Theme.accent : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }

                                RowLayout {
                                    id: seg3DRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    AppIcon {
                                        name: "icon_3d"
                                        size: 13
                                        color: root.currentLeftCardView === 0 ? Theme.textOnAccent : (mouse3D.containsMouse ? Theme.text : Theme.textSoft)
                                    }

                                    Text {
                                        text: "数字孪生视图"
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: (root.currentLeftCardView === 0) ? Theme.fontMedium : Theme.fontRegular
                                        color: root.currentLeftCardView === 0 ? Theme.textOnAccent : (mouse3D.containsMouse ? Theme.text : Theme.textSoft)
                                    }
                                }

                                MouseArea {
                                    id: mouse3D
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentLeftCardView = 0
                                }
                            }

                            // 选项 2：工位实时图像
                            Rectangle {
                                id: btnBatch
                                Layout.preferredHeight: 24
                                implicitWidth: segBatchRow.implicitWidth + 18
                                radius: 12
                                color: root.currentLeftCardView === 1 ? Theme.accent : (mouseBatch.containsMouse ? Theme.surfaceAlt : "transparent")
                                border.width: 1
                                border.color: root.currentLeftCardView === 1 ? Theme.accent : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }

                                RowLayout {
                                    id: segBatchRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    AppIcon {
                                        name: "nav_batch"
                                        size: 13
                                        color: root.currentLeftCardView === 1 ? Theme.textOnAccent : (mouseBatch.containsMouse ? Theme.text : Theme.textSoft)
                                    }

                                    Text {
                                        text: "工位实时图像"
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: (root.currentLeftCardView === 1) ? Theme.fontMedium : Theme.fontRegular
                                        color: root.currentLeftCardView === 1 ? Theme.textOnAccent : (mouseBatch.containsMouse ? Theme.text : Theme.textSoft)
                                    }
                                }

                                MouseArea {
                                    id: mouseBatch
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentLeftCardView = 1
                                }
                            }
                        }

                        ToolTip.visible: mouse3D.containsMouse || mouseBatch.containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: "点击切换数字孪生视图与工位实时图像"
                    }
                }

                Label {
                    text: root.currentLeftCardView === 0 ? "Carrier 载具数字孪生三维交互 · 左键旋转 · 右键平移 · 滚轮缩放" : "12 工位点检图像实时回传 · 点击卡片进入全屏缩放检验"
                    color: Theme.muted
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                }

                // 主工作台视窗容器（3D 数字孪生 与 工位实时图像网格）
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // 1. 3D 工作台视窗容器 (保活 OpenGL/3D 缓存，仅控制 visible)
                    Rectangle {
                        id: processDiagram
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: Theme.fieldFill
                        border.width: 1
                        border.color: Theme.borderMuted
                        clip: true
                        visible: root.currentLeftCardView === 0

                        DesignShow {
                            id: designShow
                            anchors.fill: parent
                            showHeader: false
                            onSelectedTagChanged: {
                                var w = root.tagNameToWheel(selectedTag);
                                if (root.selectedWheel !== w) {
                                    root.selectedWheel = w;
                                }
                            }
                        }
                    }

                    // 2. 工位实时图像网格容器 (嵌入模式，委派外层 ZoomOverlay)
                    RealtimeStationImageView {
                        id: realtimeStationImageView
                        anchors.fill: parent
                        visible: root.currentLeftCardView === 1
                        embeddedMode: true
                        externalViewer: imagePreview
                    }
                }
            }
        }

        // ===== 右栏：当前检测 HUD 遥测矩阵 =====
        // ===== 右栏：当前检测 HUD 遥测矩阵 (自适应数据紧凑宽度，放大左侧3D区域) =====
        Rectangle {
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.preferredWidth: 380
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
                    Layout.fillHeight: false
                    spacing: 8

                    Rectangle {
                        width: 4
                        height: 18
                        radius: 2
                        color: Theme.borderStrong
                    }

                    Label {
                        text: "当前点检遥测数据"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontTitle
                        font.weight: Theme.fontMedium
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredHeight: 22
                        implicitWidth: hintRow.implicitWidth + 12
                        radius: Theme.radiusPill
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.borderMuted

                        RowLayout {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: 4

                            AppIcon {
                                name: "icon_eye"
                                size: 11
                                color: Theme.muted
                            }

                            Label {
                                text: "轻触查看原图"
                                color: Theme.muted
                                font.pixelSize: Theme.fontMicro
                            }
                        }
                    }
                }

                // 第一行：统计指标汇总栏 (固定高度，紧凑布局)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 48
                    spacing: 8

                    // 当前架号卡片
                    Rectangle {
                        Layout.preferredWidth: 108
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: currentRack > 0 ? Theme.accent : Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 4

                            ColumnLayout {
                                spacing: 1
                                Layout.alignment: Qt.AlignVCenter
                                Label {
                                    text: "当前架号"
                                    color: Theme.textSoft
                                    font.pixelSize: Theme.fontMicro
                                }
                                Label {
                                    text: "RACK NO."
                                    color: Theme.muted
                                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontMicro
                                    font.letterSpacing: Theme.letterSpacingWide
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Label {
                                text: currentRack > 0 ? (currentRack < 10 ? "0" + currentRack : String(currentRack)) : "--"
                                color: currentRack > 0 ? Theme.accent : Theme.muted
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontDisplay
                                font.weight: Theme.fontBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    // 遥测计数与损耗率
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8

                            Item {
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                id: currentRackStatsRow
                                spacing: 6
                                Layout.alignment: Qt.AlignVCenter

                                Repeater {
                                    model: [
                                        {
                                            title: "NG 次数",
                                            value: currentRack > 0 ? String(currentRackNgCount) : "--",
                                            accent: (currentRack > 0 && currentRackNgCount > 0) ? Theme.danger : Theme.muted,
                                            background: (currentRack > 0 && currentRackNgCount > 0) ? Theme.dangerSoft : Theme.surfaceAlt,
                                            border: (currentRack > 0 && currentRackNgCount > 0) ? Theme.dangerBorder : Theme.borderMuted
                                        },
                                        {
                                            title: "检测总数",
                                            value: currentRack > 0 ? String(currentRackTotalCount) : "--",
                                            accent: currentRack > 0 ? Theme.accent : Theme.muted,
                                            background: currentRack > 0 ? Theme.activeSubtle : Theme.surfaceAlt,
                                            border: currentRack > 0 ? Theme.accentPressed : Theme.borderMuted
                                        },
                                        {
                                            title: "NG 损耗率",
                                            value: (currentRack > 0 && currentRackTotalCount > 0) ? (Number(currentRackNgRate).toFixed(1) + "%") : "--",
                                            accent: (currentRack > 0 && currentRackNgRate > 0) ? Theme.warn : (currentRack > 0 ? Theme.ok : Theme.muted),
                                            background: (currentRack > 0 && currentRackNgRate > 0) ? Theme.warnSoft : (currentRack > 0 ? Theme.okSoft : Theme.surfaceAlt),
                                            border: (currentRack > 0 && currentRackNgRate > 0) ? Theme.warn : (currentRack > 0 ? Theme.okBorder : Theme.borderMuted)
                                        }
                                    ]

                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.preferredHeight: 34
                                        Layout.preferredWidth: 68
                                        Layout.fillWidth: true
                                        radius: Theme.radiusMicro
                                        color: modelData.background
                                        border.width: 1
                                        border.color: modelData.border

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.title
                                                color: Theme.textSoft
                                                font.family: Theme.fontSans
                                                font.pixelSize: Theme.fontMicro
                                            }

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.value
                                                color: modelData.accent
                                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                                font.pixelSize: Theme.fontCaption
                                                font.weight: Theme.fontBold
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 走行轮面板 (上)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.fieldFill
                    border.width: 1
                    border.color: Theme.borderMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 3
                                height: 13
                                radius: 1.5
                                color: Theme.walkWheel
                            }
                            Label {
                                text: "走行轮（1～8）"
                                color: Theme.walkWheel
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontMedium
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "当前判定"
                                color: Theme.muted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 14
                            }
                            Label {
                                text: "合格率"
                                color: Theme.muted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 26
                            }
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: walkListCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: walkListCol
                                width: parent.width
                                spacing: 3

                                Repeater {
                                    model: root.effectiveWalkingWheels
                                    delegate: wheelResultDelegate
                                }

                                Item {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
                // 驱动轮面板 (下)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusSmall
                    color: Theme.fieldFill
                    border.width: 1
                    border.color: Theme.borderMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 3
                                height: 13
                                radius: 1.5
                                color: Theme.driveWheel
                            }
                            Label {
                                text: "驱动轮（9～16）"
                                color: Theme.driveWheel
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.fontMedium
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "当前判定"
                                color: Theme.muted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 14
                            }
                            Label {
                                text: "合格率"
                                color: Theme.muted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 26
                            }
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: driveListCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: driveListCol
                                width: parent.width
                                spacing: 3

                                Repeater {
                                    model: root.effectiveDriveWheels
                                    delegate: wheelResultDelegate
                                }

                                Item {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
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
}
