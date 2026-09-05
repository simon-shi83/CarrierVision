import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    property url viewerSource: ""
    property string titleText: ""
    property string subtitleText: ""
    property real userZoom: 1.0
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 12.0
    readonly property real fitScale: {
        if (preview.implicitWidth <= 0 || preview.implicitHeight <= 0 || flick.width <= 0 || flick.height <= 0) {
            return 1.0
        }

        return Math.min(
                    Math.max(0.1, (flick.width - 48) / preview.implicitWidth),
                    Math.max(0.1, (flick.height - 48) / preview.implicitHeight))
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

    function openViewer(sourceUrl, title, subtitle) {
        viewerSource = sourceUrl
        titleText = title
        subtitleText = subtitle
        userZoom = 1.0
        root.z = 99999
        visible = true
        forceActiveFocus()
        Qt.callLater(function() { root.forceActiveFocus(); root.z = 99999; })
        centerContent()
    }

    function closeViewer() { visible = false; viewerSource = "" }
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

    // 图像可平移缩放区域
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 16
        clip: true
        contentWidth: Math.max(width, preview.implicitWidth * root.contentScale)
        contentHeight: Math.max(height, preview.implicitHeight * root.contentScale)
        interactive: contentWidth > width || contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Item {
            width: flick.contentWidth
            height: flick.contentHeight

            Image {
                id: preview
                source: root.viewerSource
                sourceSize.width: 8192
                sourceSize.height: 8192
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectFit
                width: Math.max(1, implicitWidth * root.contentScale)
                height: Math.max(1, implicitHeight * root.contentScale)
                anchors.centerIn: parent
                smooth: true
                onStatusChanged: { if (status === Image.Ready) root.resetView() }
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

                Label {
                    text: root.titleText
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeH3
                    font.bold: true
                    elide: Label.ElideRight
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
