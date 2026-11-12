import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

// 图像窗口的缩放工具组：缩小 / 当前比例 / 放大 / 适应窗口 / 1:1 原始像素。
// 只发出意图信号，缩放计算由所在窗口完成。
Rectangle {
    id: root

    // 相对“适应窗口”的缩放倍率（1.0 = 适应窗口）
    property real zoom: 1.0
    // 相对原始像素的显示比例（1.0 = 1:1），用于百分比读数
    property real pixelScale: 1.0
    property bool canZoomIn: true
    property bool canZoomOut: true

    signal zoomInRequested()
    signal zoomOutRequested()
    signal fitRequested()
    signal actualSizeRequested()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + Theme.space1 * 2
    radius: Theme.radiusSmall
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.borderMuted

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2

        IconButton {
            objectName: "viewerZoomOut"
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            bordered: false
            iconName: "icon_minus"
            iconSize: 14
            enabled: root.canZoomOut
            toolTipText: "缩小（-）"
            onClicked: root.zoomOutRequested()
        }

        Text {
            Layout.preferredWidth: 48
            horizontalAlignment: Text.AlignHCenter
            text: Math.round(root.pixelScale * 100) + "%"
            color: Theme.text
            font.family: Theme.fontSans
            font.features: Theme.fontFeaturesTabular
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontMedium

            ToolTip.visible: pctMouse.containsMouse
            ToolTip.delay: 400
            ToolTip.text: "相对原始像素的显示比例"
            MouseArea { id: pctMouse; anchors.fill: parent; hoverEnabled: true }
        }

        IconButton {
            objectName: "viewerZoomIn"
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            bordered: false
            iconName: "icon_plus"
            iconSize: 14
            enabled: root.canZoomIn
            toolTipText: "放大（+）"
            onClicked: root.zoomInRequested()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            color: Theme.borderMuted
        }

        IconButton {
            objectName: "viewerZoomFit"
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            bordered: false
            iconName: "icon_fit"
            iconSize: 14
            toolTipText: "适应窗口（0）"
            onClicked: root.fitRequested()
        }

        IconButton {
            objectName: "viewerZoomActual"
            Layout.preferredHeight: 26
            bordered: false
            text: "1:1"
            tabularText: true
            toolTipText: "原始像素（1），双击图像也可切换"
            onClicked: root.actualSizeRequested()
        }
    }
}
