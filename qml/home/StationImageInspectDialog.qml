import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Dialog {
    id: inspectDialog

    parent: Overlay.overlay
    modal: true
    dim: true
    focus: true
    padding: 0
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    margins: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    width: Math.min(1560, Math.max(960, parent ? Math.floor(parent.width * 0.92) : 1200))
    height: Math.min(960, Math.max(680, parent ? Math.floor(parent.height * 0.90) : 800))
    anchors.centerIn: parent

    // =========================================================================
    // 对话框核心数据属性
    // =========================================================================
    property int slotIndex: -1
    property var imageModel: null
    property var currentItemObject: null

    property url viewerSource: ""
    property string titleText: ""
    property string subtitleText: ""
    property real userZoom: 1.0
    readonly property real minZoom: 0.3
    readonly property real maxZoom: 16.0

    property bool isLiveUpdating: false
    property bool showingA: true
    property string sourceA: ""
    property string sourceB: ""
    property bool showSidePanel: true

    readonly property var activePreview: showingA ? previewA : previewB
    readonly property var pendingPreview: showingA ? previewB : previewA
    readonly property real currentImageWidth: activePreview.implicitWidth > 0 ? activePreview.implicitWidth : pendingPreview.implicitWidth
    readonly property real currentImageHeight: activePreview.implicitHeight > 0 ? activePreview.implicitHeight : pendingPreview.implicitHeight

    readonly property real fitScale: {
        if (currentImageWidth <= 0 || currentImageHeight <= 0 || flick.width <= 0 || flick.height <= 0) {
            return 1.0;
        }
        return Math.min(Math.max(0.1, (flick.width - 48) / currentImageWidth), Math.max(0.1, (flick.height - 48) / currentImageHeight));
    }
    readonly property real contentScale: fitScale * userZoom

    // 模态背景遮罩
    Overlay.modal: Rectangle {
        color: Theme.bgOverlay
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animNormal
            }
        }
    }

    // 对话框主体背景
    background: Rectangle {
        color: Theme.bgCard
        radius: Theme.radiusXl
        border.color: Theme.borderStrong
        border.width: 1
        clip: true
    }

    // =========================================================================
    // 打开 / 刷新 / 关闭 方法
    // =========================================================================
    function openViewer(sourceUrl, title, subtitle, sIdx, model) {
        slotIndex = (typeof sIdx !== 'undefined' && sIdx !== null) ? sIdx : -1;
        imageModel = (typeof model !== 'undefined' && model !== null) ? model : ((typeof appController !== 'undefined' && appController) ? appController.currentImagesModel : null);
        syncItemObject();

        viewerSource = sourceUrl || "";
        titleText = title || (slotIndex >= 0 ? ("CAM " + (slotIndex < 9 ? "0" : "") + (slotIndex + 1)) : "工位图像检验");
        subtitleText = subtitle || "";
        isLiveUpdating = false;
        userZoom = 1.0;

        showingA = true;
        sourceA = String(viewerSource || "");
        sourceB = "";
        previewA.source = sourceA;
        previewB.source = "";

        inspectDialog.open();
        inspectDialog.forceActiveFocus();
        Qt.callLater(function () {
            centerContent();
        });
    }

    function closeViewer() {
        inspectDialog.close();
        viewerSource = "";
        sourceA = "";
        sourceB = "";
        previewA.source = "";
        previewB.source = "";
        slotIndex = -1;
        currentItemObject = null;
        isLiveUpdating = false;
    }

    function syncItemObject() {
        if (slotIndex >= 0 && imageModel && slotIndex < imageModel.count) {
            currentItemObject = imageModel.itemObjectAt(slotIndex);
        } else {
            currentItemObject = null;
        }
    }

    function refreshCurrentSlot() {
        if (slotIndex < 0)
            return;
        syncItemObject();
        if (!currentItemObject)
            return;
        var u = String(currentItemObject.fileUrl || "");
        var p = String(currentItemObject.filePath || "");
        var newSrc = "";
        if (u.length > 0) {
            newSrc = u;
        } else if (p.length > 0) {
            var normalized = p.replace(/\\/g, "/");
            if (/^[a-zA-Z]:\//.test(normalized))
                newSrc = "file:///" + normalized;
            else if (normalized.startsWith("/"))
                newSrc = "file://" + normalized;
            else
                newSrc = normalized;
        }
        if (newSrc.length === 0)
            return;
        titleText = (currentItemObject.serial && currentItemObject.serial.length > 0) ? currentItemObject.serial : (currentItemObject.fileName || ("CAM " + (slotIndex < 9 ? "0" : "") + (slotIndex + 1)));
        subtitleText = "工位相机 #" + (slotIndex + 1) + " ╎ " + (currentItemObject.receivedAtText || "");

        if (String(viewerSource) !== newSrc) {
            isLiveUpdating = true;
            updateLiveSource(newSrc);
        }
    }

    function updateLiveSource(newSrc) {
        if (!newSrc || newSrc.length === 0)
            return;
        viewerSource = newSrc;
        if (showingA) {
            sourceB = newSrc;
            previewB.source = newSrc;
        } else {
            sourceA = newSrc;
            previewA.source = newSrc;
        }
    }

    // =========================================================================
    // 实时联动监听
    // =========================================================================
    Connections {
        target: (inspectDialog.visible && inspectDialog.slotIndex >= 0 && typeof appController !== 'undefined') ? appController : null
        function onSlotUpdated(slot) {
            if (slot === inspectDialog.slotIndex) {
                inspectDialog.refreshCurrentSlot();
            }
        }
    }

    Connections {
        target: (inspectDialog.visible && inspectDialog.slotIndex >= 0 && inspectDialog.imageModel) ? inspectDialog.imageModel : null
        ignoreUnknownSignals: true
        function onDataChanged(topLeft, bottomRight) {
            var start = (topLeft && typeof topLeft.row !== 'undefined') ? topLeft.row : 0;
            var end = (bottomRight && typeof bottomRight.row !== 'undefined') ? bottomRight.row : -1;
            if (inspectDialog.slotIndex >= start && inspectDialog.slotIndex <= end) {
                inspectDialog.refreshCurrentSlot();
            }
        }
        function onModelReset() {
            inspectDialog.refreshCurrentSlot();
        }
    }

    // =========================================================================
    // 视口平移与缩放逻辑
    // =========================================================================
    function resetView() {
        userZoom = 1.0;
        centerContent();
    }

    function adjustZoom(multiplier, focusX, focusY) {
        const oldScale = contentScale;
        const nextZoom = Math.max(minZoom, Math.min(maxZoom, userZoom * multiplier));
        if (Math.abs(nextZoom - userZoom) < 0.0001)
            return;
        const contentFocusX = flick.contentX + focusX;
        const contentFocusY = flick.contentY + focusY;
        userZoom = nextZoom;
        const ratio = contentScale / oldScale;
        flick.contentX = Math.max(0, contentFocusX * ratio - focusX);
        flick.contentY = Math.max(0, contentFocusY * ratio - focusY);
        clampContent();
    }

    function centerContent() {
        flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2);
        flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2);
    }

    function clampContent() {
        const maxX = Math.max(0, flick.contentWidth - flick.width);
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX));
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY));
    }

    Timer {
        id: cleanTimer
        interval: Theme.animFast + 60
        repeat: false
        property string target: ""
        onTriggered: {
            if (target === "A" && !inspectDialog.showingA) {
                previewA.source = "";
                inspectDialog.sourceA = "";
            } else if (target === "B" && inspectDialog.showingA) {
                previewB.source = "";
                inspectDialog.sourceB = "";
            }
        }
    }

    // =========================================================================
    // 对话框内部布局体系
    // =========================================================================
    contentItem: ColumnLayout {
        spacing: 0

        // 1. 高精工业顶栏
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.bgCardElevated
            radius: Theme.radiusXl

            // 修复圆角遮挡
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.radiusXl
                color: parent.color
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                // 相机徽章容器
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: Theme.radiusMd
                    color: Theme.primaryGlow
                    border.color: Theme.primary
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_camera"
                        size: 20
                        color: Theme.primaryLight
                    }
                }

                // 标题信息流
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        spacing: 8

                        Label {
                            text: inspectDialog.titleText
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeH2
                            font.bold: true
                            elide: Label.ElideRight
                        }

                        // 相机工位胶囊
                        Rectangle {
                            visible: inspectDialog.slotIndex >= 0
                            Layout.preferredHeight: 20
                            implicitWidth: camTagText.implicitWidth + 12
                            radius: Theme.radiusPill
                            color: Theme.bgCardActive
                            border.color: Theme.primary
                            border.width: 1

                            Text {
                                id: camTagText
                                anchors.centerIn: parent
                                text: "CAM " + (inspectDialog.slotIndex < 9 ? "0" : "") + (inspectDialog.slotIndex + 1)
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.primaryLight
                            }
                        }

                        // 实时监控联动呼吸灯
                        Rectangle {
                            visible: inspectDialog.slotIndex >= 0
                            Layout.preferredHeight: 20
                            implicitWidth: liveTagRow.implicitWidth + 12
                            radius: Theme.radiusPill
                            color: Theme.okBg
                            border.color: Theme.okBorder
                            border.width: 1

                            RowLayout {
                                id: liveTagRow
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Theme.ok

                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: inspectDialog.visible && inspectDialog.slotIndex >= 0
                                        NumberAnimation {
                                            from: 1.0
                                            to: 0.2
                                            duration: 700
                                        }
                                        NumberAnimation {
                                            from: 0.2
                                            to: 1.0
                                            duration: 700
                                        }
                                    }
                                }

                                Label {
                                    text: "实时工位监控中"
                                    color: Theme.okLight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeTiny
                                    font.bold: true
                                }
                            }
                        }
                    }

                    Label {
                        text: inspectDialog.subtitleText.length > 0 ? inspectDialog.subtitleText : "支持鼠标滚轮平滑缩放、按住拖拽平移，点检数据实时更新"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Label.ElideRight
                    }
                }

                // 数据面板展开/折叠切换按钮
                ActionButton {
                    text: inspectDialog.showSidePanel ? "收起指标" : "展开指标"
                    variant: inspectDialog.showSidePanel ? "primary" : "secondary"
                    Layout.preferredHeight: 34
                    Layout.preferredWidth: 92
                    visible: inspectDialog.currentItemObject !== null
                    onClicked: {
                        inspectDialog.showSidePanel = !inspectDialog.showSidePanel;
                    }
                }

                // 优雅关闭按钮
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: closeBtnMouse.containsMouse ? Theme.bgCardActive : "transparent"
                    border.width: 1
                    border.color: closeBtnMouse.containsMouse ? Theme.borderHover : Theme.borderSubtle

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animFast
                        }
                    }

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_close"
                        size: 16
                        color: closeBtnMouse.containsMouse ? Theme.textPrimary : Theme.textMuted
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: inspectDialog.closeViewer()
                    }
                }
            }
        }

        // 2. 主体工作视窗 (左侧大图全景视口 + 可选右侧遥测数据抽屉)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // 主画布容器
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // 2.1 大图可平移缩放 Flickable 视口
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    contentWidth: Math.max(width, inspectDialog.currentImageWidth * inspectDialog.contentScale)
                    contentHeight: Math.max(height, inspectDialog.currentImageHeight * inspectDialog.contentScale)
                    interactive: contentWidth > width || contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        width: flick.contentWidth
                        height: flick.contentHeight

                        // 双缓冲 A
                        Image {
                            id: previewA
                            anchors.centerIn: parent
                            sourceSize: Qt.size(8192, 8192)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectFit
                            width: Math.max(1, implicitWidth * inspectDialog.contentScale)
                            height: Math.max(1, implicitHeight * inspectDialog.contentScale)
                            smooth: true
                            opacity: (inspectDialog.showingA && status === Image.Ready) ? 1.0 : 0.0
                            visible: opacity > 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.animFast
                                }
                            }

                            onStatusChanged: {
                                if (status === Image.Ready) {
                                    if (!inspectDialog.showingA && inspectDialog.sourceA !== "") {
                                        inspectDialog.showingA = true;
                                        cleanTimer.target = "B";
                                        cleanTimer.restart();
                                    } else if (!inspectDialog.isLiveUpdating) {
                                        inspectDialog.resetView();
                                    }
                                }
                            }
                        }

                        // 双缓冲 B
                        Image {
                            id: previewB
                            anchors.centerIn: parent
                            sourceSize: Qt.size(8192, 8192)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectFit
                            width: Math.max(1, implicitWidth * inspectDialog.contentScale)
                            height: Math.max(1, implicitHeight * inspectDialog.contentScale)
                            smooth: true
                            opacity: (!inspectDialog.showingA && status === Image.Ready) ? 1.0 : 0.0
                            visible: opacity > 0.0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.animFast
                                }
                            }

                            onStatusChanged: {
                                if (status === Image.Ready) {
                                    if (inspectDialog.showingA && inspectDialog.sourceB !== "") {
                                        inspectDialog.showingA = false;
                                        cleanTimer.target = "A";
                                        cleanTimer.restart();
                                    } else if (!inspectDialog.isLiveUpdating) {
                                        inspectDialog.resetView();
                                    }
                                }
                            }
                        }

                        // 滚轮缩放监听
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: function (wheel) {
                                wheel.accepted = true;
                                inspectDialog.adjustZoom(wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15), wheel.x, wheel.y);
                            }
                        }
                    }
                }

                // 2.2 底部悬浮控制坞 (Floating Control Dock)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 24
                    height: 44
                    implicitWidth: dockRow.implicitWidth + 24
                    radius: Theme.radiusPill
                    color: Theme.bgPopup
                    border.color: Theme.borderMedium
                    border.width: 1

                    RowLayout {
                        id: dockRow
                        anchors.centerIn: parent
                        spacing: 8

                        // 缩小按钮
                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: zoomOutMouse.containsMouse ? Theme.bgCardActive : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "－"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: zoomOutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: inspectDialog.adjustZoom(1 / 1.25, flick.width / 2, flick.height / 2)
                            }
                        }

                        // 缩放百分比胶囊
                        Rectangle {
                            Layout.preferredHeight: 26
                            implicitWidth: zoomPctText.implicitWidth + 14
                            radius: Theme.radiusPill
                            color: Theme.bgCardElevated
                            border.color: Theme.borderSubtle
                            border.width: 1

                            Text {
                                id: zoomPctText
                                anchors.centerIn: parent
                                text: Math.round(inspectDialog.userZoom * 100) + "%"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.primaryLight
                            }
                        }

                        // 放大按钮
                        Rectangle {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: zoomInMouse.containsMouse ? Theme.bgCardActive : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "＋"
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: zoomInMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: inspectDialog.adjustZoom(1.25, flick.width / 2, flick.height / 2)
                            }
                        }

                        // 竖向分割线
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 18
                            color: Theme.divider
                        }

                        // 1:1 原图查看
                        ActionButton {
                            text: "1:1 原图"
                            variant: "secondary"
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 70
                            onClicked: {
                                if (inspectDialog.fitScale > 0) {
                                    inspectDialog.userZoom = 1.0 / inspectDialog.fitScale;
                                    inspectDialog.centerContent();
                                }
                            }
                        }

                        // 适应屏幕
                        ActionButton {
                            text: "适应视口"
                            variant: "secondary"
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 74
                            onClicked: inspectDialog.resetView()
                        }
                    }
                }
            }

            // 2.3 右侧抽屉式点检遥测数据卡片 (Collapsible Sidebar)
            Rectangle {
                id: telemetryDrawer
                Layout.preferredWidth: (inspectDialog.showSidePanel && inspectDialog.currentItemObject !== null) ? 320 : 0
                Layout.fillHeight: true
                color: Theme.bgCardElevated
                clip: true
                visible: Layout.preferredWidth > 0

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: Theme.animNormal
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Theme.borderSubtle
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    // 遥测栏头部
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Theme.primary
                        }

                        Label {
                            text: "工位点检遥测指标"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeH3
                            font.bold: true
                        }
                    }

                    // 判定结果大幅徽章
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        radius: Theme.radiusMd
                        readonly property bool isPass: inspectDialog.currentItemObject ? (inspectDialog.currentItemObject.result === 1) : true
                        color: isPass ? Theme.okBg : Theme.ngBg
                        border.color: isPass ? Theme.okBorder : Theme.ngBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: 19
                                color: parent.parent.isPass ? Theme.ok : Theme.ng

                                AppIcon {
                                    anchors.centerIn: parent
                                    name: parent.parent.isPass ? "icon_check_circle" : "icon_close"
                                    size: 20
                                    color: "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: parent.parent.isPass ? "点检状态: OK 正常" : "点检状态: NG 异常"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    color: parent.parent.isPass ? Theme.okLight : Theme.ngLight
                                }

                                Text {
                                    text: parent.parent.isPass ? "符合产线高精公差规范" : "存在偏差或缺陷，请核验"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeTiny
                                    color: Theme.textMuted
                                }
                            }
                        }
                    }

                    // 关键测量值矩阵
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusMd
                        color: Theme.bgCard
                        border.color: Theme.borderSubtle
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label {
                                text: "位移与几何遥测"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            MetricRow {
                                labelName: "载具架号 (Rack)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.rack) : "-"
                                valColor: Theme.primaryLight
                            }

                            MetricRow {
                                labelName: "工位槽位 (Slot)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.slot) : "-"
                                valColor: Theme.primaryLight
                            }

                            MetricRow {
                                labelName: "点检轮次 (Round)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.roundNumber) : "-"
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.divider
                            }

                            MetricRow {
                                labelName: "测量间距 (Min)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.distance) : "-"
                                unitName: "mm"
                            }

                            MetricRow {
                                labelName: "测量极值 (Max)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.distMax) : "-"
                                unitName: "mm"
                            }

                            MetricRow {
                                labelName: "标准基准 (Norm)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.distNorm) : "-"
                                unitName: "mm"
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            // 归档路径详情
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: "文件归档信息"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeTiny
                                    font.bold: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: inspectDialog.currentItemObject ? inspectDialog.currentItemObject.fileName : ""
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    color: Theme.textSecondary
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 测量指标行组件
    component MetricRow: RowLayout {
        property string labelName: ""
        property string metricValue: ""
        property string unitName: ""
        property color valColor: Theme.textPrimary
        Layout.fillWidth: true

        Text {
            text: labelName
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
        }
        Text {
            text: metricValue + (unitName.length > 0 ? (" " + unitName) : "")
            color: valColor
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }
    }
}
