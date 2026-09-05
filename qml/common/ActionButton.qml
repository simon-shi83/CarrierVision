import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: buttonRoot

    // ===== 样式属性配置 =====
    property string variant: "primary" // "primary" | "secondary" | "danger" | "success" | "outline"
    property int btnRadius: Theme.radiusMd
    property color accentColor: Theme.primaryLight
    property color bgColor: {
        if (variant === "secondary") return Theme.bgCardElevated
        if (variant === "danger") return Theme.ng
        if (variant === "success") return Theme.ok
        if (variant === "outline") return "transparent"
        return Theme.primary
    }
    property color hoverColor: {
        if (variant === "secondary") return Theme.bgCardActive
        if (variant === "danger") return Theme.ngLight
        if (variant === "success") return Theme.okLight
        if (variant === "outline") return Theme.primaryGlow
        return Theme.primaryLight
    }
    property color textColor: {
        if (variant === "outline") return Theme.primaryLight
        if (variant === "secondary") return Theme.textPrimary
        return "#ffffff"
    }
    property color hoverTextColor: {
        if (variant === "outline") return "#ffffff"
        return "#ffffff"
    }
    property color borderColor: {
        if (variant === "outline") return Theme.primary
        if (variant === "secondary") return Theme.borderMedium
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
            ? Theme.bgCard 
            : (buttonRoot.down 
                ? Qt.darker(buttonRoot.hoverColor, 1.2) 
                : (buttonRoot.isHovered ? buttonRoot.hoverColor : buttonRoot.bgColor))
        
        border.width: 1
        border.color: !buttonRoot.enabled 
            ? Theme.borderSubtle 
            : (buttonRoot.isHovered 
                ? (buttonRoot.variant === "danger" ? Theme.ngLight : Theme.borderHover) 
                : buttonRoot.borderColor)

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        // 柔和光晕层
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: buttonRoot.isHovered ? (buttonRoot.variant === "danger" ? Theme.ngBg : Theme.primaryGlow) : "transparent"
            visible: buttonRoot.enabled
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    contentItem: Text {
        id: contentText
        text: buttonRoot.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        font.bold: true
        color: !buttonRoot.enabled 
            ? Theme.textDisabled 
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
