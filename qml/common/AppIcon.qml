import QtQuick 2.15
import QtQuick.Effects

Item {
    id: root
    property string name: ""
    property color color: Theme.textSecondary
    property int size: 18

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property string iconSource: {
        if (!name || name.length === 0) return ""
        if (name.indexOf("/") !== -1 || name.indexOf(":") !== -1)
            return name
        return "qrc:/qt/qml/CarrierVision/icons/" + name + ".svg"
    }

    Image {
        id: rawIcon
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: Math.max(32, root.size * 2)
        sourceSize.height: Math.max(32, root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: rawIcon
        source: rawIcon
        colorization: 1.0
        colorizationColor: root.color
        visible: rawIcon.status === Image.Ready
    }
}
