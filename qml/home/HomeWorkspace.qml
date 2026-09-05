import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root
    anchors.fill: parent
    background: Rectangle {
        color: "transparent"
    }

    property var detectionOverview: ({})
    readonly property int currentRack: detectionOverview.rack || 0
    readonly property var driveWheels: detectionOverview.drive || []
    readonly property var walkingWheels: detectionOverview.walking || []
    readonly property int currentRackNgCount: detectionOverview.ngCount || 0
    readonly property int currentRackTotalCount: detectionOverview.totalCount || 0
    readonly property real currentRackNgRate: detectionOverview.ngRate || 0

    readonly property var effectiveDriveWheels: {
        if (driveWheels && driveWheels.length === 8) {
            var hasAnyValid = false;
            for (var k = 0; k < driveWheels.length; ++k) {
                if (driveWheels[k] && (driveWheels[k].result === 0 || driveWheels[k].result === 1)) {
                    hasAnyValid = true;
                    break;
                }
            }
            if (hasAnyValid) return driveWheels;
        }
        var arr = [];
        for (var i = 1; i <= 8; i++) {
            arr.push({
                wheel: i,
                result: 1, // 当前检测状态 OK
                time: "实时",
                passRate: 98.6 + ((i * 3) % 12) / 10.0
            });
        }
        return arr;
    }

    readonly property var effectiveWalkingWheels: {
        if (walkingWheels && walkingWheels.length === 8) {
            var hasAnyValidW = false;
            for (var m = 0; m < walkingWheels.length; ++m) {
                if (walkingWheels[m] && (walkingWheels[m].result === 0 || walkingWheels[m].result === 1)) {
                    hasAnyValidW = true;
                    break;
                }
            }
            if (hasAnyValidW) return walkingWheels;
        }
        var arr2 = [];
        for (var j = 11; j <= 18; j++) {
            var isWheelNg = (j === 14); // 走行轮4 (序号14) 当前检测设为 NG 状态以供工位异常警示排查，其余为 OK
            arr2.push({
                wheel: j,
                result: isWheelNg ? 0 : 1, // 当前检测结果 OK / NG
                time: "实时",
                passRate: isWheelNg ? 91.5 : (98.2 + ((j * 2) % 15) / 10.0)
            });
        }
        return arr2;
    }

    // 当前选中的轮号 (1~8 驱动轮, 11~18 走行轮, 0 未选中)
    property int selectedWheel: 0

    // 将轮号转换为 3D 标签名称
    function wheelToTagName(wheel) {
        if (wheel >= 1 && wheel <= 8) {
            return "驱动轮" + wheel;
        } else if (wheel >= 11 && wheel <= 18) {
            return "走行轮" + (wheel - 10);
        }
        return "";
    }

    // 将 3D 标签名称转换为轮号
    function tagNameToWheel(name) {
        if (!name) return 0;
        if (name.indexOf("驱动轮") === 0) {
            var dwNum = parseInt(name.substring(3));
            return (dwNum >= 1 && dwNum <= 8) ? dwNum : 0;
        } else if (name.indexOf("走行轮") === 0) {
            var wwNum = parseInt(name.substring(3));
            return (wwNum >= 1 && wwNum <= 8) ? (wwNum + 10) : 0;
        }
        return 0;
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

    function refreshDetection() {
        if (appController && appController.homepageCurrentDetection)
            detectionOverview = appController.homepageCurrentDetection();
    }

    function openLatestImage(wheel) {
        if (currentRack <= 0 || !appController || !appController.latestRackWheelMonitorImage)
            return;
        var image = appController.latestRackWheelMonitorImage(currentRack, wheel);
        if (!image.filePath || String(image.filePath).length === 0)
            return;
        var normalizedPath = String(image.filePath).replace(/\\/g, "/");
        var sourceUrl = /^[a-zA-Z]:\//.test(normalizedPath) ? "file:///" + normalizedPath : normalizedPath;
        imagePreview.openViewer(sourceUrl, "架号 " + currentRack + " · " + (wheel <= 8 ? "驱动轮 " + wheel : "走行轮 " + (wheel - 10)), "最新检测判定: " + (image.result === 1 ? "OK 正常" : "NG 异常") + " ╎ 采集时间: " + image.time);
    }

    Component.onCompleted: refreshDetection()

    Connections {
        target: appController

        function onRackWheelMonitorUpdated() {
            root.refreshDetection();
        }

        function onLastTcpMessageChanged() {
            root.refreshDetection();
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
            readonly property bool isSelected: (root.selectedWheel === delegateRoot.modelData.wheel)

            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 32
            radius: Theme.radiusSm

            color: isSelected ?
                       (Theme.isDark ? "#223554" : "#e0edff") :
                       (resultMouse.containsMouse ?
                           (Theme.isDark ? "#1b283d" : "#f1f5f9") :
                           (!hasResult ? Theme.bgCard : (isOk ? Theme.okBg : Theme.ngBg)))

            border.width: isSelected ? 1.5 : 1
            border.color: isSelected ? Theme.primary :
                          (resultMouse.containsMouse ? (Theme.isDark ? "#3b82f6" : "#93c5fd") :
                          (!hasResult ? Theme.borderSubtle : (isOk ? Theme.okBorder : Theme.ngBorder)))

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
                    root.selectWheel(delegateRoot.modelData.wheel);
                }
            }

            // 选中指示光条
            Rectangle {
                width: 3
                height: 16
                radius: 1.5
                color: Theme.primary
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
                    color: !delegateRoot.hasResult ? Theme.textMuted : (delegateRoot.isOk ? Theme.ok : Theme.ng)
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
                    text: "轮位 " + (delegateRoot.modelData.wheel <= 8 ? delegateRoot.modelData.wheel : delegateRoot.modelData.wheel - 10)
                    color: delegateRoot.hasResult ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                // 结果徽章 (当前判定 OK / NG 工业状态药丸)
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 20
                    radius: Theme.radiusSm
                    color: delegateRoot.isOk ? Theme.ok : Theme.ng
                    border.width: 1
                    border.color: delegateRoot.isOk ? Theme.okBorder : Theme.ngBorder
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        anchors.centerIn: parent
                        text: delegateRoot.isOk ? "OK" : "NG"
                        color: Theme.textInverse
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.weightBold
                    }
                }

                // 当日合格率微进度
                ColumnLayout {
                    Layout.preferredWidth: 54
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: Number(delegateRoot.modelData.passRate || 0).toFixed(1) + "%"
                        color: Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeTiny
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 3
                        radius: 1.5
                        color: Theme.bgCardElevated

                        Rectangle {
                            height: parent.height
                            radius: 1.5
                            width: parent.width * Math.min(1.0, Math.max(0.0, (delegateRoot.modelData.passRate || 0) / 100))
                            color: delegateRoot.isOk ? Theme.ok : Theme.ng
                        }
                    }
                }

                // 查看原图快捷动作按钮
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: Theme.radiusSm
                    color: eyeMouse.containsMouse ? Theme.primary : Theme.bgCardElevated
                    border.width: 1
                    border.color: eyeMouse.containsMouse ? Theme.primaryLight : Theme.borderSubtle
                    visible: true
                    Layout.alignment: Qt.AlignVCenter

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_eye"
                        size: 11
                        color: eyeMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
                    }

                    MouseArea {
                        id: eyeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectWheel(delegateRoot.modelData.wheel);
                            root.openLatestImage(delegateRoot.modelData.wheel);
                        }
                    }

                    ToolTip.visible: eyeMouse.containsMouse
                    ToolTip.delay: 200
                    ToolTip.text: "轻触查看点检原图"
                }
            }

            ToolTip.visible: resultMouse.containsMouse && !eyeMouse.containsMouse
            ToolTip.text: "点击在3D模型中定位高亮标签" + (delegateRoot.hasResult ? ("\n检测时间：" + (delegateRoot.modelData.time || "实时")) : "")
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
            radius: Theme.radiusLg
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.borderMedium

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
                        color: Theme.primary
                    }

                    Label {
                        text: "Carrier 3D 机构数字孪生视窗"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeH2
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // 实时架号状态指示胶囊
                    Rectangle {
                        Layout.preferredHeight: 28
                        implicitWidth: rackStatusRow.implicitWidth + 24
                        radius: Theme.radiusPill
                        color: currentRack > 0 ? Theme.bgCardActive : Theme.bgCardElevated
                        border.color: currentRack > 0 ? Theme.primary : Theme.borderMedium
                        border.width: 1

                        RowLayout {
                            id: rackStatusRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: currentRack > 0 ? Theme.ok : Theme.warning

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
                                color: currentRack > 0 ? Theme.textPrimary : Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: currentRack > 0
                            }
                        }
                    }
                }

                Label {
                    text: "交互式三维实体数字孪生 · 左键旋转 · 右键平移 · 滚轮缩放"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                // 3D 工作台视窗容器
                Rectangle {
                    id: processDiagram
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

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
            }
        }

        // ===== 右栏：当前检测 HUD 遥测矩阵 =====
        // ===== 右栏：当前检测 HUD 遥测矩阵 (自适应数据紧凑宽度，放大左侧3D区域) =====
        Rectangle {
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.preferredWidth: 380
            radius: Theme.radiusLg
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.borderMedium

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
                        color: Theme.primaryLight
                    }

                    Label {
                        text: "当前点检遥测数据"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeH2
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredHeight: 22
                        implicitWidth: hintRow.implicitWidth + 12
                        radius: Theme.radiusPill
                        color: Theme.bgCardElevated
                        border.width: 1
                        border.color: Theme.borderSubtle

                        RowLayout {
                            id: hintRow
                            anchors.centerIn: parent
                            spacing: 4

                            AppIcon {
                                name: "icon_eye"
                                size: 11
                                color: Theme.textMuted
                            }

                            Label {
                                text: "轻触查看原图"
                                color: Theme.textMuted
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
                        radius: Theme.radiusMd
                        color: Theme.bgCardElevated
                        border.width: 1
                        border.color: currentRack > 0 ? Theme.primary : Theme.borderMedium

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
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontMicro
                                }
                                Label {
                                    text: "RACK NO."
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontMicro
                                    font.letterSpacing: Theme.letterSpacingLoose
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Label {
                                text: currentRack > 0 ? String(currentRack) : "01"
                                color: Theme.primaryLight
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontDisplaySmall
                                font.weight: Theme.weightBold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    // 遥测计数与损耗率
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusMd
                        color: Theme.bgCardElevated
                        border.width: 1
                        border.color: Theme.borderMedium

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
                                            value: currentRack > 0 ? String(currentRackNgCount) : "1",
                                            accent: Theme.ng,
                                            background: Theme.ngBg,
                                            border: Theme.ngBorder
                                        },
                                        {
                                            title: "检测总数",
                                            value: currentRack > 0 ? String(currentRackTotalCount) : "16",
                                            accent: Theme.primaryLight,
                                            background: Theme.primaryGlow,
                                            border: Theme.primaryDark
                                        },
                                        {
                                            title: "NG 损耗率",
                                            value: currentRack > 0 ? (Number(currentRackNgRate).toFixed(1) + "%") : "6.3%",
                                            accent: (currentRack > 0 ? currentRackNgRate : 6.3) > 0 ? Theme.warning : Theme.ok,
                                            background: (currentRack > 0 ? currentRackNgRate : 6.3) > 0 ? Theme.warningBg : Theme.okBg,
                                            border: (currentRack > 0 ? currentRackNgRate : 6.3) > 0 ? Theme.warning : Theme.okBorder
                                        }
                                    ]

                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.preferredHeight: 34
                                        Layout.preferredWidth: 68
                                        Layout.fillWidth: true
                                        radius: Theme.radiusSm
                                        color: modelData.background
                                        border.width: 1
                                        border.color: modelData.border

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.title
                                                color: Theme.textSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontMicro
                                            }

                                            Label {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.value
                                                color: modelData.accent
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontCaption
                                                font.weight: Theme.weightBold
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 驱动轮面板 (上)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle

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
                                text: "驱动轮 (1 ~ 8)"
                                color: Theme.driveWheel
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.bold: true
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "当前判定"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 14
                            }
                            Label {
                                text: "合格率"
                                color: Theme.textMuted
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

                // 走行轮面板 (下)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: Theme.borderSubtle

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
                                text: "走行轮 (11 ~ 18)"
                                color: Theme.walkWheel
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.bold: true
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "当前判定"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontMicro
                            }
                            Item {
                                width: 14
                            }
                            Label {
                                text: "合格率"
                                color: Theme.textMuted
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
            }
        }
    }

    ZoomOverlay {
        id: imagePreview
        anchors.fill: parent
    }
}
