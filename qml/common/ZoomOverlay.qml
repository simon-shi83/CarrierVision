import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

// 通用图像放大窗口：铺满所在页面的模态浮层。标题栏提供缩放工具组、另存为和关闭；
// 图像区始终为深色底，判读不受界面主题影响。实时工位联动时随槽位刷新图像。
Item {
    id: root

    property url viewerSource: ""
    property string titleText: ""
    property string subtitleText: ""
    property real userZoom: 1.0
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 12.0

    // 实时工位联动属性
    property int activeSlotIndex: -1
    property var targetModel: null
    property bool isLiveUpdating: false

    property bool showingA: true
    property string sourceA: ""
    property string sourceB: ""

    // 原图文件信息（宽高、大小、格式），由 AppController 读取文件头得到
    property var imageInfo: ({})

    readonly property var activePreview: showingA ? previewA : previewB
    readonly property var pendingPreview: showingA ? previewB : previewA
    readonly property real currentImageWidth: activePreview.implicitWidth > 0 ? activePreview.implicitWidth : pendingPreview.implicitWidth
    readonly property real currentImageHeight: activePreview.implicitHeight > 0 ? activePreview.implicitHeight : pendingPreview.implicitHeight
    readonly property bool imageReady: currentImageWidth > 0 && currentImageHeight > 0
    readonly property bool imageLoading: !imageReady && (previewA.status === Image.Loading || previewB.status === Image.Loading)
    readonly property bool imageFailed: !imageReady && (previewA.status === Image.Error || previewB.status === Image.Error)

    readonly property real fitScale: {
        if (currentImageWidth <= 0 || currentImageHeight <= 0 || flick.width <= 0 || flick.height <= 0) {
            return 1.0
        }

        return Math.min(
                    Math.max(0.01, (flick.width - Theme.space5 * 2) / currentImageWidth),
                    Math.max(0.01, (flick.height - Theme.space5 * 2) / currentImageHeight))
    }
    readonly property real contentScale: fitScale * userZoom
    // 原始像素宽度（大图解码时可能被 sourceSize 限制，比例按原图计算）
    readonly property real originalWidth: (imageInfo && imageInfo.width > 0) ? imageInfo.width : currentImageWidth
    readonly property real pixelScale: originalWidth > 0 ? contentScale * currentImageWidth / originalWidth : contentScale

    visible: false
    z: 99999
    focus: visible

    function formatBytes(bytes) {
        if (!(bytes > 0)) return ""
        if (bytes >= 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB"
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB"
        return bytes + " B"
    }

    readonly property string imageInfoText: {
        var parts = []
        if (imageInfo && imageInfo.width > 0 && imageInfo.height > 0) parts.push(imageInfo.width + " × " + imageInfo.height + " px")
        else if (imageReady) parts.push(Math.round(currentImageWidth) + " × " + Math.round(currentImageHeight) + " px")
        var size = formatBytes(imageInfo ? imageInfo.bytes : 0)
        if (size.length > 0) parts.push(size)
        if (imageInfo && imageInfo.format && imageInfo.format.length > 0) parts.push(imageInfo.format)
        return parts.join("  ·  ")
    }

    function loadImageInfo(src) {
        if (typeof appController !== "undefined" && appController && typeof appController.imageFileInfo === "function")
            imageInfo = appController.imageFileInfo(String(src || ""))
        else
            imageInfo = ({})
    }

    function openViewer(sourceUrl, title, subtitle, slotIndex, model) {
        viewerSource = sourceUrl
        titleText = title || ""
        subtitleText = subtitle || ""
        activeSlotIndex = (typeof slotIndex !== 'undefined' && slotIndex !== null) ? slotIndex : -1
        targetModel = (typeof model !== 'undefined' && model !== null) ? model : null
        isLiveUpdating = false
        userZoom = 1.0
        loadImageInfo(sourceUrl)

        showingA = true
        sourceA = String(sourceUrl || "")
        sourceB = ""
        previewA.source = sourceA
        previewB.source = ""

        root.z = 99999
        visible = true
        openAnim.restart()
        forceActiveFocus()
        Qt.callLater(function() { root.forceActiveFocus(); root.z = 99999; })
        centerContent()
    }

    function updateLiveSource(newSrc) {
        if (!newSrc || newSrc.length === 0) return
        viewerSource = newSrc
        loadImageInfo(newSrc)
        if (showingA) {
            sourceB = newSrc
            previewB.source = newSrc
        } else {
            sourceA = newSrc
            previewA.source = newSrc
        }
    }

    function refreshCurrentSlot() {
        if (activeSlotIndex < 0) return
        var model = targetModel || ((typeof appController !== 'undefined' && appController) ? appController.currentImagesModel : null)
        if (!model || activeSlotIndex >= model.count) return
        var obj = model.itemObjectAt(activeSlotIndex)
        if (!obj) return

        var u = String(obj.fileUrl || "")
        var p = String(obj.filePath || "")
        var newSrc = ""
        if (u.length > 0) {
            newSrc = u
        } else if (p.length > 0) {
            var normalized = p.replace(/\\/g, "/")
            if (/^[a-zA-Z]:\//.test(normalized)) newSrc = "file:///" + normalized
            else if (normalized.startsWith("/")) newSrc = "file://" + normalized
            else newSrc = normalized
        }
        if (newSrc.length === 0) return

        var newTitle = (obj.serial && obj.serial.length > 0) ? obj.serial : (obj.fileName || ("CAM " + (activeSlotIndex + 1)))
        var newSubtitle = "工位相机 #" + (activeSlotIndex + 1) + " · " + (obj.receivedAtText || "")

        titleText = newTitle
        subtitleText = newSubtitle

        if (String(viewerSource) !== newSrc) {
            isLiveUpdating = true
            updateLiveSource(newSrc)
        }
    }

    Connections {
        target: (root.visible && root.activeSlotIndex >= 0 && typeof appController !== 'undefined') ? appController : null
        ignoreUnknownSignals: true
        function onSlotUpdated(slot) {
            if (slot === root.activeSlotIndex) {
                root.refreshCurrentSlot()
            }
        }
    }

    Connections {
        target: (root.visible && root.activeSlotIndex >= 0 && root.targetModel) ? root.targetModel : null
        ignoreUnknownSignals: true
        function onDataChanged(topLeft, bottomRight) {
            var start = (topLeft && typeof topLeft.row !== 'undefined') ? topLeft.row : 0
            var end = (bottomRight && typeof bottomRight.row !== 'undefined') ? bottomRight.row : -1
            if (root.activeSlotIndex >= start && root.activeSlotIndex <= end) {
                root.refreshCurrentSlot()
            }
        }
        function onModelReset() {
            root.refreshCurrentSlot()
        }
    }

    function closeViewer() {
        visible = false
        viewerSource = ""
        sourceA = ""
        sourceB = ""
        previewA.source = ""
        previewB.source = ""
        activeSlotIndex = -1
        targetModel = null
        isLiveUpdating = false
        imageInfo = ({})
    }

    function resetView() { userZoom = 1.0; centerContent() }

    // focusX / focusY 为视口坐标（相对 flick 左上角），缩放后保持该点下的图像位置不动
    function adjustZoom(multiplier, focusX, focusY) {
        const oldScale = contentScale
        const nextZoom = Math.max(minZoom, Math.min(maxZoom, userZoom * multiplier))
        if (Math.abs(nextZoom - userZoom) < 0.0001) return

        const contentFocusX = flick.contentX + focusX
        const contentFocusY = flick.contentY + focusY
        userZoom = nextZoom
        const ratio = contentScale / oldScale
        flick.contentX = Math.max(0, contentFocusX * ratio - focusX)
        flick.contentY = Math.max(0, contentFocusY * ratio - focusY)
        clampContent()
    }

    function zoomBy(multiplier) { adjustZoom(multiplier, flick.width / 2, flick.height / 2) }

    // 显示为原始像素（1:1）
    function showActualSize(focusX, focusY) {
        if (!imageReady || fitScale <= 0) return
        const target = Math.max(minZoom, Math.min(maxZoom, (originalWidth / currentImageWidth) / fitScale))
        adjustZoom(target / userZoom,
                   typeof focusX === "number" ? focusX : flick.width / 2,
                   typeof focusY === "number" ? focusY : flick.height / 2)
    }

    function toggleActualSize(focusX, focusY) {
        if (Math.abs(pixelScale - 1.0) < 0.01) resetView()
        else showActualSize(focusX, focusY)
    }

    function centerContent() {
        flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2)
        flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2)
    }

    function clampContent() {
        const maxX = Math.max(0, flick.contentWidth - flick.width)
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX))
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY))
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            saver.open()
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            zoomBy(1.25)
        } else if (event.key === Qt.Key_Minus) {
            zoomBy(1 / 1.25)
        } else if (event.key === Qt.Key_0) {
            resetView()
        } else if (event.key === Qt.Key_1) {
            showActualSize()
        } else {
            return
        }
        event.accepted = true
    }

    Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Escape) {
            closeViewer()
            event.accepted = true
        }
    }

    Timer {
        id: cleanTimer
        interval: Theme.animFast + 60
        repeat: false
        property string target: ""
        onTriggered: {
            if (target === "A" && !root.showingA) {
                previewA.source = ""
                root.sourceA = ""
            } else if (target === "B" && root.showingA) {
                previewB.source = ""
                root.sourceB = ""
            }
        }
    }

    // 遮罩：点击窗口外区域关闭
    Rectangle {
        anchors.fill: parent
        color: Theme.dialogOverlay

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.closeViewer()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: frame; property: "opacity"; from: 0.0; to: 1.0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
        NumberAnimation { target: frame; property: "scale"; from: 0.985; to: 1.0; duration: Theme.animNormal; easing.type: Easing.OutCubic }
    }

    // 窗口主体：标题栏 + 深色图像区
    Rectangle {
        id: frame
        objectName: "zoomViewerFrame"
        anchors.fill: parent
        anchors.margins: Theme.space5
        radius: Theme.radiusLarge
        color: Theme.imageStage
        border.width: 1
        border.color: Theme.borderMuted

        // 吞掉窗口内的点击，避免穿透到遮罩被关闭
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        // 标题栏
        Rectangle {
            id: titleBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 56
            radius: Theme.radiusLarge - 1
            color: Theme.surface

            // 补齐标题栏下沿的直角
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Theme.radiusLarge
                color: parent.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.borderMuted
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.color: Theme.borderMuted
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        name: root.activeSlotIndex >= 0 ? "icon_camera" : "icon_image"
                        size: 16
                        color: Theme.textSoft
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        Label {
                            Layout.fillWidth: implicitWidth > width
                            Layout.maximumWidth: implicitWidth
                            text: root.titleText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            font.weight: Theme.fontMedium
                            elide: Label.ElideMiddle
                        }

                        // 实时工位联动标识
                        Rectangle {
                            Layout.preferredHeight: 20
                            implicitWidth: liveBadgeRow.implicitWidth + 12
                            radius: Theme.radiusPill
                            color: Theme.okSoft
                            border.color: Theme.okBorder
                            border.width: 1
                            visible: root.activeSlotIndex >= 0

                            RowLayout {
                                id: liveBadgeRow
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: Theme.radiusPill
                                    color: Theme.ok

                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: root.visible && root.activeSlotIndex >= 0
                                        NumberAnimation { from: 1.0; to: 0.2; duration: Theme.animPulse }
                                        NumberAnimation { from: 0.2; to: 1.0; duration: Theme.animPulse }
                                    }
                                }

                                Label {
                                    text: "实时联动"
                                    color: Theme.ok
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.fontMedium
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.subtitleText
                        color: Theme.muted
                        font.family: Theme.fontSans
                        font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
                        elide: Label.ElideRight
                    }
                }

                ViewerZoomControls {
                    zoom: root.userZoom
                    pixelScale: root.pixelScale
                    canZoomIn: root.userZoom < root.maxZoom - 0.0001
                    canZoomOut: root.userZoom > root.minZoom + 0.0001
                    onZoomInRequested: root.zoomBy(1.25)
                    onZoomOutRequested: root.zoomBy(1 / 1.25)
                    onFitRequested: root.resetView()
                    onActualSizeRequested: root.showActualSize()
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 20
                    color: Theme.borderMuted
                }

                IconButton {
                    objectName: "zoomSaveAsButton"
                    iconName: "icon_save"
                    text: saver.busy ? "保存中" : "另存为"
                    enabled: saver.canSave && root.imageReady
                    toolTipText: "把原图保存到本地（Ctrl+S）"
                    onClicked: saver.open()
                }

                IconButton {
                    iconName: "icon_close"
                    bordered: false
                    toolTipText: "关闭（Esc）"
                    onClicked: root.closeViewer()
                }
            }
        }

        // 图像区
        Item {
            id: stage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBar.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 1
            anchors.topMargin: 0
            clip: true

            // 图像可平移缩放区域
            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                contentWidth: Math.max(width, root.currentImageWidth * root.contentScale)
                contentHeight: Math.max(height, root.currentImageHeight * root.contentScale)
                interactive: contentWidth > width || contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Item {
                    width: flick.contentWidth
                    height: flick.contentHeight

                    Image {
                        id: previewA
                        anchors.centerIn: parent
                        sourceSize.width: 8192
                        sourceSize.height: 8192
                        asynchronous: true
                        cache: false // 大图单张可达数百 MB，不进入共享图片缓存
                        fillMode: Image.PreserveAspectFit
                        width: Math.max(1, implicitWidth * root.contentScale)
                        height: Math.max(1, implicitHeight * root.contentScale)
                        // 放大到原始像素两倍以上时关闭平滑，便于看清像素边界
                        smooth: root.pixelScale < 2.0
                        opacity: (root.showingA && status === Image.Ready) ? 1.0 : 0.0
                        visible: opacity > 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.animFast }
                        }

                        onStatusChanged: {
                            if (status === Image.Ready) {
                                if (!root.showingA && root.sourceA !== "") {
                                    root.showingA = true
                                    cleanTimer.target = "B"
                                    cleanTimer.restart()
                                } else if (!root.isLiveUpdating) {
                                    root.resetView()
                                }
                            }
                        }
                    }

                    Image {
                        id: previewB
                        anchors.centerIn: parent
                        sourceSize.width: 8192
                        sourceSize.height: 8192
                        asynchronous: true
                        cache: false // 大图单张可达数百 MB，不进入共享图片缓存
                        fillMode: Image.PreserveAspectFit
                        width: Math.max(1, implicitWidth * root.contentScale)
                        height: Math.max(1, implicitHeight * root.contentScale)
                        smooth: root.pixelScale < 2.0
                        opacity: (!root.showingA && status === Image.Ready) ? 1.0 : 0.0
                        visible: opacity > 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.animFast }
                        }

                        onStatusChanged: {
                            if (status === Image.Ready) {
                                if (root.showingA && root.sourceB !== "") {
                                    root.showingA = false
                                    cleanTimer.target = "A"
                                    cleanTimer.restart()
                                } else if (!root.isLiveUpdating) {
                                    root.resetView()
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: flick.interactive ? (flick.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                        onWheel: function(wheel) {
                            wheel.accepted = true
                            // wheel.x/y 是内容坐标，换算为视口坐标后作为缩放焦点
                            root.adjustZoom(wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15),
                                            wheel.x - flick.contentX, wheel.y - flick.contentY)
                        }
                    }

                    TapHandler {
                        onDoubleTapped: function(eventPoint) {
                            root.toggleActualSize(eventPoint.position.x - flick.contentX,
                                                  eventPoint.position.y - flick.contentY)
                        }
                    }
                }
            }

            // 加载中 / 加载失败提示
            Rectangle {
                anchors.centerIn: parent
                visible: root.imageLoading || root.imageFailed
                width: stateRow.implicitWidth + Theme.space5 * 2
                height: 40
                radius: Theme.radiusSmall
                color: Theme.overlayFill

                RowLayout {
                    id: stateRow
                    anchors.centerIn: parent
                    spacing: Theme.space2

                    AppIcon {
                        visible: root.imageFailed
                        name: "icon_warning"
                        size: 16
                        color: Theme.warn
                    }

                    Text {
                        text: root.imageFailed ? "图像加载失败，原图可能已被清理" : "图像加载中…"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }

            // 左下角图像信息与操作提示
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.space3
                visible: root.imageReady
                height: 28
                width: infoRow.implicitWidth + Theme.space3 * 2
                radius: Theme.radiusSmall
                color: Theme.overlayFill

                RowLayout {
                    id: infoRow
                    anchors.centerIn: parent
                    spacing: Theme.space3

                    Text {
                        visible: text.length > 0
                        text: root.imageInfoText
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
                    }

                    Rectangle {
                        visible: root.imageInfoText.length > 0
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
                sourceUrl: String(root.viewerSource)
            }
        }
    }
}
