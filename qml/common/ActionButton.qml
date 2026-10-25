import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: buttonRoot

    // ===== 样式属性配置 =====
    // primary：页面主操作（强调色）；secondary：普通操作；danger：不可撤销操作的确认
    property string variant: "primary" // "primary" | "secondary" | "danger"
    property int btnRadius: Theme.radiusSmall

    readonly property bool solid: variant !== "secondary"
    readonly property color bgColor: variant === "danger" ? Theme.danger
                                     : (variant === "secondary" ? Theme.surfaceAlt : Theme.accent)
    readonly property color pressedColor: variant === "danger" ? Theme.dangerPressed
                                          : (variant === "secondary" ? Theme.pressed : Theme.accentPressed)
    readonly property color textColor: solid ? Theme.textOnAccent : Theme.text

    property bool isHovered: false

    implicitHeight: 36
    implicitWidth: Math.max(72, contentText.implicitWidth + Theme.space5)
    padding: 0

    background: Rectangle {
        radius: buttonRoot.btnRadius
        color: !buttonRoot.enabled
            ? Theme.surfaceAlt
            : (buttonRoot.down
                ? buttonRoot.pressedColor
                : (buttonRoot.isHovered && !buttonRoot.solid ? Theme.hover : buttonRoot.bgColor))

        border.width: buttonRoot.solid && buttonRoot.enabled ? 0 : 1
        border.color: !buttonRoot.enabled
            ? Theme.borderMuted
            : (buttonRoot.isHovered ? Theme.borderStrong : Theme.border)

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        // 实底按钮的悬停叠加层：只改变明度，不引入新的色相
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.solidHoverOverlay
            visible: buttonRoot.enabled && buttonRoot.solid && buttonRoot.isHovered && !buttonRoot.down
        }
    }

    contentItem: Text {
        id: contentText
        text: buttonRoot.text
        font.family: Theme.fontSans
        font.pixelSize: Theme.fontBody
        font.weight: Theme.fontMedium
        color: buttonRoot.enabled ? buttonRoot.textColor : Theme.disabled
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: buttonRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
        onEntered: buttonRoot.isHovered = true
        onExited: buttonRoot.isHovered = false
        onPressed: { buttonRoot.down = true }
        onReleased: { buttonRoot.down = false }
        onClicked: { buttonRoot.clicked() }
    }
}
