import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

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

    readonly property var activePreview: showingA ? previewA : previewB
    readonly property var pendingPreview: showingA ? previewB : previewA
    readonly property real currentImageWidth: activePreview.implicitWidth > 0 ? activePreview.implicitWidth : pendingPreview.implicitWidth
    readonly property real currentImageHeight: activePreview.implicitHeight > 0 ? activePreview.implicitHeight : pendingPreview.implicitHeight

    readonly property real fitScale: {
        if (currentImageWidth <= 0 || currentImageHeight <= 0 || flick.width <= 0 || flick.height <= 0) {
            return 1.0
        }

        return Math.min(
                    Math.max(0.1, (flick.width - 48) / currentImageWidth),
                    Math.max(0.1, (flick.height - 48) / currentImageHeight))
    }
    readonly property real contentScale: fitScale * userZoom

    visible: false
    z: 99999
    focus: visible

    // 高端毛玻璃深色半透明遮罩
    Rectangle {
        anchors.fill: parent
        color: Theme.bgOverlay
        opacity: root.visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
    }

    function openViewer(sourceUrl, title, subtitle, slotIndex, model) {
        viewerSource = sourceUrl
        titleText = title || ""
        subtitleText = subtitle || ""
        activeSlotIndex = (typeof slotIndex !== 'undefined' && slotIndex !== null) ? slotIndex : -1
        targetModel = (typeof model !== 'undefined' && model !== null) ? model : null
        isLiveUpdating = false
        userZoom = 1.0

        showingA = true
        sourceA = String(sourceUrl || "")
        sourceB = ""
        previewA.source = sourceA
        previewB.source = ""

        root.z = 99999
        visible = true
        forceActiveFocus()
        Qt.callLater(function() { root.forceActiveFocus(); root.z = 99999; })
        centerContent()
    }

    function updateLiveSource(newSrc) {
        if (!newSrc || newSrc.length === 0) return
        viewerSource = newSrc
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
        var newSubtitle = "工位相机 #" + (activeSlotIndex + 1) + " ╎ " + (obj.receivedAtText || "")

        titleText = newTitle
        subtitleText = newSubtitle

        if (String(viewerSource) !== newSrc) {
            isLiveUpdating = true
            updateLiveSource(newSrc)
        }
    }

    Connections {
        target: (root.visible && root.activeSlotIndex >= 0 && typeof appController !== 'undefined') ? appController : null
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
    }

    function resetView() { userZoom = 1.0; centerContent() }

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

    // 图像可平移缩放区域
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 16
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
                cache: true
                fillMode: Image.PreserveAspectFit
                width: Math.max(1, implicitWidth * root.contentScale)
                height: Math.max(1, implicitHeight * root.contentScale)
                smooth: true
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
                cache: true
                fillMode: Image.PreserveAspectFit
                width: Math.max(1, implicitWidth * root.contentScale)
                height: Math.max(1, implicitHeight * root.contentScale)
                smooth: true
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
                onWheel: function(wheel) {
                    wheel.accepted = true
                    root.adjustZoom(wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15), wheel.x, wheel.y)
                }
            }
        }
    }

    // 顶部浮动控制胶囊面板
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        height: 60
        radius: Theme.radiusLg
        color: Theme.bgPopup
        border.width: 1
        border.color: Theme.borderMedium

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 16
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Theme.radiusSm
                color: Theme.primaryGlow
                border.color: Theme.primary
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "🔍"
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    spacing: 8

                    Label {
                        text: root.titleText
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeH3
                        font.bold: true
                        elide: Label.ElideRight
                    }

                    // 实时工位联动标识胶囊
                    Rectangle {
                        Layout.preferredHeight: 20
                        implicitWidth: liveBadgeRow.implicitWidth + 12
                        radius: Theme.radiusPill
                        color: Theme.primaryGlow
                        border.color: Theme.primary
                        border.width: 1
                        visible: root.activeSlotIndex >= 0

                        RowLayout {
                            id: liveBadgeRow
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.primary

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    running: root.visible && root.activeSlotIndex >= 0
                                    NumberAnimation { from: 1.0; to: 0.2; duration: 700 }
                                    NumberAnimation { from: 0.2; to: 1.0; duration: 700 }
                                }
                            }

                            Label {
                                text: "实时监控联动"
                                color: Theme.primaryLight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeTiny
                                font.bold: true
                            }
                        }
                    }
                }

                Label {
                    text: root.subtitleText + " ╎ 缩放率: " + Math.round(root.userZoom * 100) + "% (滚轮平滑缩放 / 拖拽平移)"
                    color: Theme.textSecondary
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Label.ElideRight
                }
            }

            ActionButton {
                text: "1:1 原图"
                variant: "secondary"
                Layout.preferredWidth: 76
                Layout.preferredHeight: 34
                onClicked: root.resetView()
            }

            ActionButton {
                text: "关闭 (Esc)"
                variant: "primary"
                Layout.preferredWidth: 90
                Layout.preferredHeight: 34
                onClicked: root.closeViewer()
            }
        }
    }
}
