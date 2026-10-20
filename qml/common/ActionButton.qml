import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: buttonRoot

    // ===== 样式属性配置 =====
    property string variant: "primary" // "primary" | "secondary" | "danger" | "success" | "outline"
    property int btnRadius: Theme.radiusSmall
    property color accentColor: Theme.accent
    property color bgColor: {
        if (variant === "secondary") return Theme.surfaceAlt
        if (variant === "danger") return Theme.danger
        if (variant === "success") return Theme.ok
        if (variant === "outline") return "transparent"
        return Theme.accent
    }
    property color hoverColor: {
        if (variant === "secondary") return Theme.pressed
        if (variant === "danger") return Theme.danger
        if (variant === "success") return Theme.ok
        if (variant === "outline") return Theme.activeSubtle
        return Theme.accent
    }
    property color textColor: {
        if (variant === "outline") return Theme.accent
        if (variant === "secondary") return Theme.text
        return Theme.textOnAccent
    }
    property color hoverTextColor: {
        return Theme.textOnAccent
    }
    property color borderColor: {
        if (variant === "outline") return Theme.accent
        if (variant === "secondary") return Theme.border
        return "transparent"
    }

    property bool isHovered: false

    implicitHeight: 36
    implicitWidth: Math.max(72, contentText.implicitWidth + 24)
    padding: 0

    background: Rectangle {
        id: bgRect
        radius: buttonRoot.btnRadius
        color: !buttonRoot.enabled 
            ? Theme.surface 
            : (buttonRoot.down 
                ? Qt.darker(buttonRoot.hoverColor, 1.2) 
                : (buttonRoot.isHovered ? buttonRoot.hoverColor : buttonRoot.bgColor))
        
        border.width: 1
        border.color: !buttonRoot.enabled 
            ? Theme.borderMuted 
            : (buttonRoot.isHovered 
                ? (buttonRoot.variant === "danger" ? Theme.danger : Theme.borderStrong) 
                : buttonRoot.borderColor)

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        // 柔和光晕层
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: buttonRoot.isHovered ? (buttonRoot.variant === "danger" ? Theme.dangerSoft : Theme.hover) : "transparent"
            visible: buttonRoot.enabled
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    contentItem: Text {
        id: contentText
        text: buttonRoot.text
        font.family: Theme.fontSans
        font.pixelSize: Theme.fontBody
        font.weight: Theme.fontMedium
        color: !buttonRoot.enabled 
            ? Theme.disabled 
            : (buttonRoot.isHovered ? buttonRoot.hoverTextColor : buttonRoot.textColor)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

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
