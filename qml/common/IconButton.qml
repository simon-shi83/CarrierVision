import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."

// 紧凑工具按钮：图标、文字或图标加文字。悬停用中性色，不用强调色；
// 用于图像窗口标题栏、缩放工具组等工具型入口。
Rectangle {
    id: root

    property string iconName: ""
    property string text: ""
    property string toolTipText: ""
    property int iconSize: 16
    // bordered：独立按钮带浅描边；false 时用于按钮组内部，只在悬停时显示底色
    property bool bordered: true
    // tabularText：数字类文字（如 1:1）用等宽数字排版
    property bool tabularText: false
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    implicitHeight: 32
    implicitWidth: text.length > 0 ? content.implicitWidth + Theme.space3 * 2 : implicitHeight
    radius: Theme.radiusSmall
    color: !enabled ? "transparent"
                    : (mouse.pressed ? Theme.pressed : (mouse.containsMouse ? Theme.hover : (bordered ? Theme.surfaceAlt : "transparent")))
    border.width: bordered ? 1 : 0
    border.color: !enabled ? Theme.borderMuted : (mouse.containsMouse ? Theme.borderStrong : Theme.borderMuted)
    opacity: enabled ? 1.0 : 0.6

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space1 + 2

        AppIcon {
            visible: root.iconName.length > 0
            name: root.iconName
            size: root.iconSize
            color: !root.enabled ? Theme.disabled : (mouse.containsMouse ? Theme.text : Theme.textSoft)
        }

        Text {
            visible: root.text.length > 0
            text: root.text
            color: !root.enabled ? Theme.disabled : Theme.text
            font.family: Theme.fontSans
            font.features: root.tabularText ? Theme.fontFeaturesTabular : ({})
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontMedium
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: mouse.containsMouse && root.toolTipText.length > 0
    ToolTip.delay: 400
    ToolTip.text: root.toolTipText
}
