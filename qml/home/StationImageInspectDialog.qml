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

    // 原图文件信息（宽高、大小、格式），由 AppController 读取文件头得到；
    // 预览按 sourceSize 降采样解码，显示比例和 1:1 按原图像素计算
    property var imageInfo: ({})
    readonly property bool imageReady: currentImageWidth > 0 && currentImageHeight > 0
    readonly property bool imageLoading: !imageReady && (previewA.status === Image.Loading || previewB.status === Image.Loading)
    readonly property bool imageFailed: !imageReady && (previewA.status === Image.Error || previewB.status === Image.Error)
    readonly property real originalWidth: (imageInfo && imageInfo.width > 0) ? imageInfo.width : currentImageWidth
    readonly property real pixelScale: originalWidth > 0 ? contentScale * currentImageWidth / originalWidth : contentScale

    function formatBytes(bytes) {
        if (!(bytes > 0))
            return "";
        if (bytes >= 1024 * 1024)
            return (bytes / 1024 / 1024).toFixed(1) + " MB";
        if (bytes >= 1024)
            return Math.round(bytes / 1024) + " KB";
        return bytes + " B";
    }

    readonly property string imageInfoText: {
        var parts = [];
        if (imageInfo && imageInfo.width > 0 && imageInfo.height > 0)
            parts.push(imageInfo.width + " × " + imageInfo.height + " px");
        else if (imageReady)
            parts.push(Math.round(currentImageWidth) + " × " + Math.round(currentImageHeight) + " px");
        var size = formatBytes(imageInfo ? imageInfo.bytes : 0);
        if (size.length > 0)
            parts.push(size);
        if (imageInfo && imageInfo.format && imageInfo.format.length > 0)
            parts.push(imageInfo.format);
        return parts.join("  ·  ");
    }

    function loadImageInfo(src) {
        if (typeof appController !== "undefined" && appController && typeof appController.imageFileInfo === "function")
            imageInfo = appController.imageFileInfo(String(src || ""));
        else
            imageInfo = ({});
    }

    // 模态背景遮罩
    Overlay.modal: Rectangle {
        color: Theme.dialogOverlay
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animNormal
            }
        }
    }

    // 对话框主体背景
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusLarge
        border.color: Theme.border
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
        loadImageInfo(viewerSource);

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
        imageInfo = ({});
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
        subtitleText = "工位相机 #" + (slotIndex + 1) + " · " + (currentItemObject.receivedAtText || "");

        if (String(viewerSource) !== newSrc) {
            isLiveUpdating = true;
            updateLiveSource(newSrc);
        }
    }

    function updateLiveSource(newSrc) {
        if (!newSrc || newSrc.length === 0)
            return;
        viewerSource = newSrc;
        loadImageInfo(newSrc);
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

    function zoomBy(multiplier) {
        adjustZoom(multiplier, flick.width / 2, flick.height / 2);
    }

    // 显示为原始像素（1:1）
    function showActualSize(focusX, focusY) {
        if (!imageReady || fitScale <= 0)
            return;
        const target = Math.max(minZoom, Math.min(maxZoom, (originalWidth / currentImageWidth) / fitScale));
        adjustZoom(target / userZoom, typeof focusX === "number" ? focusX : flick.width / 2, typeof focusY === "number" ? focusY : flick.height / 2);
    }

    function toggleActualSize(focusX, focusY) {
        if (Math.abs(pixelScale - 1.0) < 0.01)
            resetView();
        else
            showActualSize(focusX, focusY);
    }

    // 键盘：Ctrl+S 另存为，+ / - 缩放，0 适应窗口，1 原始像素
    Shortcut {
        enabled: inspectDialog.opened
        sequence: StandardKey.Save
        onActivated: saver.open()
    }
    Shortcut {
        enabled: inspectDialog.opened
        sequences: [StandardKey.ZoomIn, "=", "+"]
        onActivated: inspectDialog.zoomBy(1.25)
    }
    Shortcut {
        enabled: inspectDialog.opened
        sequences: [StandardKey.ZoomOut, "-"]
        onActivated: inspectDialog.zoomBy(1 / 1.25)
    }
    Shortcut {
        enabled: inspectDialog.opened
        sequence: "0"
        onActivated: inspectDialog.resetView()
    }
    Shortcut {
        enabled: inspectDialog.opened
        sequence: "1"
        onActivated: inspectDialog.showActualSize()
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
            color: Theme.surfaceAlt
            radius: Theme.radiusLarge

            // 修复圆角遮挡
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.radiusLarge
                color: parent.color
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderMuted
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
                    radius: Theme.radiusSmall
                    color: Theme.surface
                    border.color: Theme.borderMuted
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_camera"
                        size: 20
                        color: Theme.textSoft
                    }
                }

                // 标题信息流
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: inspectDialog.titleText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontTitle
                            font.weight: Theme.fontMedium
                            elide: Label.ElideRight
                        }

                        // 相机工位胶囊
                        Rectangle {
                            visible: inspectDialog.slotIndex >= 0
                            Layout.preferredHeight: 20
                            implicitWidth: camTagText.implicitWidth + 12
                            radius: Theme.radiusPill
                            color: Theme.surface
                            border.color: Theme.borderMuted
                            border.width: 1

                            Text {
                                id: camTagText
                                anchors.centerIn: parent
                                text: "CAM " + (inspectDialog.slotIndex < 9 ? "0" : "") + (inspectDialog.slotIndex + 1)
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.fontMedium
                                color: Theme.text
                            }
                        }

                        // 实时监控联动呼吸灯
                        Rectangle {
                            visible: inspectDialog.slotIndex >= 0
                            Layout.preferredHeight: 20
                            implicitWidth: liveTagRow.implicitWidth + 12
                            radius: Theme.radiusPill
                            color: Theme.okSoft
                            border.color: Theme.okBorder
                            border.width: 1

                            RowLayout {
                                id: liveTagRow
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: Theme.radiusPill
                                    color: Theme.ok

                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: inspectDialog.visible && inspectDialog.slotIndex >= 0
                                        NumberAnimation {
                                            from: 1.0
                                            to: 0.2
                                            duration: Theme.animPulse
                                        }
                                        NumberAnimation {
                                            from: 0.2
                                            to: 1.0
                                            duration: Theme.animPulse
                                        }
                                    }
                                }

                                Label {
                                    text: "实时工位监控中"
                                    color: Theme.ok
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.fontMedium
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: inspectDialog.subtitleText.length > 0 ? inspectDialog.subtitleText : "支持鼠标滚轮平滑缩放、按住拖拽平移，点检数据实时更新"
                        color: Theme.muted
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
                        elide: Label.ElideRight
                    }
                }

                ViewerZoomControls {
                    zoom: inspectDialog.userZoom
                    pixelScale: inspectDialog.pixelScale
                    canZoomIn: inspectDialog.userZoom < inspectDialog.maxZoom - 0.0001
                    canZoomOut: inspectDialog.userZoom > inspectDialog.minZoom + 0.0001
                    onZoomInRequested: inspectDialog.zoomBy(1.25)
                    onZoomOutRequested: inspectDialog.zoomBy(1 / 1.25)
                    onFitRequested: inspectDialog.resetView()
                    onActualSizeRequested: inspectDialog.showActualSize()
                }

                // 数据面板展开/折叠切换
                IconButton {
                    visible: inspectDialog.currentItemObject !== null
                    iconName: "icon_ruler"
                    text: inspectDialog.showSidePanel ? "收起指标" : "展开指标"
                    toolTipText: "显示或隐藏右侧点检指标"
                    onClicked: inspectDialog.showSidePanel = !inspectDialog.showSidePanel
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 20
                    color: Theme.borderMuted
                }

                IconButton {
                    objectName: "inspectSaveAsButton"
                    iconName: "icon_save"
                    text: saver.busy ? "保存中" : "另存为"
                    enabled: saver.canSave && inspectDialog.imageReady
                    toolTipText: "把原图保存到本地（Ctrl+S）"
                    onClicked: saver.open()
                }

                IconButton {
                    iconName: "icon_close"
                    bordered: false
                    toolTipText: "关闭（Esc）"
                    onClicked: inspectDialog.closeViewer()
                }
            }
        }

        // 2. 主体工作视窗 (左侧大图全景视口 + 可选右侧遥测数据抽屉)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // 主画布容器：图像区两种主题都用深色底，判读不受界面主题影响
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.imageStage
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
                            sourceSize: Qt.size(Math.min(4096, Math.max(1920, flick.width * 2)),
                                                Math.min(4096, Math.max(1080, flick.height * 2)))
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
                            sourceSize: Qt.size(Math.min(4096, Math.max(1920, flick.width * 2)),
                                                Math.min(4096, Math.max(1080, flick.height * 2)))
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
                            cursorShape: flick.interactive ? (flick.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                            onWheel: function (wheel) {
                                wheel.accepted = true;
                                // wheel.x/y 是内容坐标，换算为视口坐标后作为缩放焦点
                                inspectDialog.adjustZoom(wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15),
                                                         wheel.x - flick.contentX, wheel.y - flick.contentY);
                            }
                        }

                        TapHandler {
                            onDoubleTapped: function (eventPoint) {
                                inspectDialog.toggleActualSize(eventPoint.position.x - flick.contentX,
                                                               eventPoint.position.y - flick.contentY);
                            }
                        }
                    }
                }

                // 2.2 加载中 / 加载失败提示
                Rectangle {
                    anchors.centerIn: parent
                    visible: inspectDialog.imageLoading || inspectDialog.imageFailed
                    width: stateRow.implicitWidth + Theme.space5 * 2
                    height: 40
                    radius: Theme.radiusSmall
                    color: Theme.overlayFill

                    RowLayout {
                        id: stateRow
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        AppIcon {
                            visible: inspectDialog.imageFailed
                            name: "icon_warning"
                            size: 16
                            color: Theme.warn
                        }

                        Text {
                            text: inspectDialog.imageFailed ? "图像加载失败，原图可能已被清理" : "图像加载中…"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                }

                // 2.3 左下角图像信息与操作提示
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.space3
                    visible: inspectDialog.imageReady
                    height: 28
                    width: Math.min(parent.width - Theme.space3 * 2, infoRow.implicitWidth + Theme.space3 * 2)
                    radius: Theme.radiusSmall
                    color: Theme.overlayFill
                    clip: true

                    RowLayout {
                        id: infoRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.space3
                        spacing: Theme.space3

                        Text {
                            visible: text.length > 0
                            text: inspectDialog.imageInfoText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.features: Theme.fontFeaturesTabular
                            font.pixelSize: Theme.fontCaption
                        }

                        Rectangle {
                            visible: inspectDialog.imageInfoText.length > 0
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 12
                            color: Theme.borderMuted
                        }

                        Text {
                            text: "滚轮缩放  ·  拖拽平移  ·  双击切换 1:1"
                            color: Theme.muted
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                }

                ImageSaveAs {
                    id: saver
                    objectName: "imageSaveAs"
                    anchors.fill: parent
                    sourceUrl: String(inspectDialog.viewerSource)
                }
            }

            // 2.3 右侧抽屉式点检遥测数据卡片 (Collapsible Sidebar)
            Rectangle {
                id: telemetryDrawer
                Layout.preferredWidth: (inspectDialog.showSidePanel && inspectDialog.currentItemObject !== null) ? 320 : 0
                Layout.fillHeight: true
                color: Theme.surfaceAlt
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
                    color: Theme.borderMuted
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
                            radius: Theme.radiusPill
                            color: Theme.borderStrong
                        }

                        Label {
                            text: "工位点检遥测指标"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontMedium
                        }
                    }

                    // 判定结果大幅徽章
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        radius: Theme.radiusSmall
                        readonly property bool isPass: inspectDialog.currentItemObject ? (inspectDialog.currentItemObject.result === 1) : true
                        color: isPass ? Theme.okSoft : Theme.dangerSoft
                        border.color: isPass ? Theme.okBorder : Theme.dangerBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: Theme.radiusPill
                                color: parent.parent.isPass ? Theme.ok : Theme.danger

                                AppIcon {
                                    anchors.centerIn: parent
                                    name: parent.parent.isPass ? "icon_check_circle" : "icon_close"
                                    size: 20
                                    color: Theme.textOnAccent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: parent.parent.isPass ? "点检状态: OK 正常" : "点检状态: NG 异常"
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontBody
                                    font.weight: Theme.fontMedium
                                    color: parent.parent.isPass ? Theme.ok : Theme.danger
                                }

                                Text {
                                    text: parent.parent.isPass ? "符合产线高精公差规范" : "存在偏差或缺陷，请核验"
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontCaption
                                    color: Theme.muted
                                }
                            }
                        }
                    }

                    // 关键测量值矩阵
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.color: Theme.borderMuted
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label {
                                text: "位移与几何遥测"
                                color: Theme.textSoft
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                                font.weight: Theme.fontMedium
                            }

                            MetricRow {
                                labelName: "载具编号 (Carrier)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.carrierId !== undefined && inspectDialog.currentItemObject.carrierId > 0 ? inspectDialog.currentItemObject.carrierId : inspectDialog.currentItemObject.rack) : "-"
                                valColor: Theme.text
                            }

                            MetricRow {
                                labelName: "工位相机 (Camera)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.cameraId !== undefined && inspectDialog.currentItemObject.cameraId > 0 ? inspectDialog.currentItemObject.cameraId : (inspectDialog.slotIndex + 1)) : "-"
                                valColor: Theme.text
                            }

                            MetricRow {
                                objectName: "wheelIdentityMetric"
                                labelName: "检测轮位"
                                metricValue: appController.wheelLabel(inspectDialog.currentItemObject ? inspectDialog.currentItemObject.wheelId : 0)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.borderMuted
                            }

                            MetricRow {
                                labelName: "实测间距 (Actual)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.distance) : "-"
                                unitName: "mm"
                            }

                            MetricRow {
                                labelName: "基准距离 (Base)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.distNorm) : "-"
                                unitName: "mm"
                            }

                            MetricRow {
                                labelName: "下偏差 (Lower Tol)"
                                metricValue: inspectDialog.currentItemObject ? String(inspectDialog.currentItemObject.lowerTolerance !== undefined ? inspectDialog.currentItemObject.lowerTolerance : 0.0) : "-"
                                unitName: "mm"
                            }

                            Label {
                                visible: inspectDialog.currentItemObject && inspectDialog.currentItemObject.wheelsInfo && inspectDialog.currentItemObject.wheelsInfo.length > 0
                                text: inspectDialog.currentItemObject ? inspectDialog.currentItemObject.wheelsInfo : ""
                                color: Theme.text
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
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
                                    color: Theme.muted
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.fontMedium
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: inspectDialog.currentItemObject ? inspectDialog.currentItemObject.fileName : ""
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontMicro
                                    color: Theme.textSoft
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
        property color valColor: Theme.text
        Layout.fillWidth: true

        Text {
            text: labelName
            color: Theme.muted
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontCaption
            Layout.fillWidth: true
        }
        Text {
            text: metricValue + (unitName.length > 0 ? (" " + unitName) : "")
            color: valColor
            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontMedium
        }
    }
}
