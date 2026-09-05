import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: statusBar
    width: parent ? parent.width : 800
    height: 32
    color: Theme.bgStatusBar
    border.width: 1
    border.color: Theme.borderSubtle

    // 顶部发光微边框
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.borderSubtle
    }

    // ========== 对外属性 ==========
    property var statusItems: []

    // 默认样式
    property color backgroundColor: Theme.bgStatusBar
    property color borderColor: Theme.borderSubtle
    property color textColor: Theme.textSecondary
    property int defaultItemWidth: 0

    // 信号
    signal itemClicked(int index, var itemData)
    signal itemDoubleClicked(int index, var itemData)

    RowLayout {
        id: statusRow
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Repeater {
            id: repeater
            model: statusItems

            delegate: Rectangle {
                id: itemContainer
                color: "transparent"

                Layout.preferredWidth: {
                    if (modelData.width !== undefined && modelData.width > 0) {
                        return modelData.width
                    }
                    return implicitWidth
                }
                Layout.fillWidth: {
                    if (modelData.width === undefined || modelData.width === 0) {
                        return true
                    }
                    return false
                }
                Layout.minimumWidth: modelData.minWidth || 20
                height: parent.height

                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    // 状态微指示灯
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: modelData.textColor || Theme.ok
                        visible: modelData.modelId === "status" || modelData.modelId === "tcpstatus"
                        Layout.alignment: Qt.AlignVCenter

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: modelData.modelId === "status"
                            NumberAnimation { from: 1.0; to: 0.4; duration: 1000; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.4; to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                        }
                    }

                    // 图标
                    Text {
                        id: iconText
                        text: modelData.iconText || ""
                        font.pixelSize: Theme.fontBody
                        color: modelData.textColor || Theme.textSecondary
                        visible: text !== "" && modelData.modelId !== "status" && modelData.modelId !== "tcpstatus"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // 文本
                    Text {
                        id: itemText
                        text: modelData.text || ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontCaption
                        font.weight: modelData.modelId === "status" ? Theme.weightSemiBold : Theme.weightNormal
                        color: modelData.textColor || Theme.textSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // 分隔线
                Rectangle {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: -6
                    }
                    width: 1
                    height: 14
                    color: Theme.divider
                    visible: index < statusItems.length - 1
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true

                    Rectangle {
                        anchors.fill: parent
                        color: itemMouse.containsMouse ? Theme.bgCardActive : "transparent"
                        radius: Theme.radiusSm
                        opacity: 0.6
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    onClicked: statusBar.itemClicked(index, modelData)
                    onDoubleClicked: statusBar.itemDoubleClicked(index, modelData)
                }

                ToolTip {
                    id: itemToolTip
                    visible: itemMouse.containsMouse && Boolean(modelData && modelData.tooltip !== undefined)
                    text: (modelData && modelData.tooltip) ? String(modelData.tooltip) : ""
                    delay: 500
                    background: Rectangle {
                        color: Theme.bgPopup
                        border.color: Theme.borderMedium
                        radius: Theme.radiusSm
                    }
                    contentItem: Text {
                        text: itemToolTip.text
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }
        }
    }

    // ========== 辅助方法保持不变以确保完整后端兼容 ==========
    function updateItem(index, newData) {
        if (index >= 0 && index < statusItems.length) {
            var newItems = statusItems.slice()
            var obj = Object.assign({}, newItems[index])
            for (var key in newData) {
                obj[key] = newData[key]
            }
            newItems[index] = obj
            statusItems = newItems
        }
    }

    function updateText(index, text) {
        updateItem(index, { text: text })
    }

    function updateColor(index, color) {
        updateItem(index, { textColor: color })
    }

    function updateIcon(index, icon) {
        updateItem(index, { iconText: icon })
    }

    function updateById(modelId, newData) {
        var newItems = statusItems.slice()
        for (var i = 0; i < newItems.length; i++) {
            if (newItems[i].modelId === modelId) {
                var obj = Object.assign({}, newItems[i])
                for (var key in newData) {
                    obj[key] = newData[key]
                }
                newItems[i] = obj
                statusItems = newItems
                return true
            }
        }
        return false
    }

    function updateTextById(modelId, text) {
        return updateById(modelId, { text: text })
    }

    function updateColorById(modelId, color) {
        return updateById(modelId, { textColor: color })
    }

    function updateIconById(modelId, icon) {
        return updateById(modelId, { iconText: icon })
    }

    function getItemById(modelId) {
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i].modelId === modelId) {
                return statusItems[i]
            }
        }
        return null
    }

    function findIndexById(modelId) {
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i].modelId === modelId) {
                return i
            }
        }
        return -1
    }

    function addItem(itemData) {
        var newItems = statusItems.slice()
        newItems.push(itemData)
        statusItems = newItems
    }

    function removeItemById(modelId) {
        var newItems = statusItems.slice()
        for (var i = 0; i < newItems.length; i++) {
            if (newItems[i].modelId === modelId) {
                newItems.splice(i, 1)
                statusItems = newItems
                return true
            }
        }
        return false
    }

    function clearItems() {
        statusItems = []
    }

    function updateStatus(text) {
        if (statusItems.length > 0) {
            updateText(0, text)
        }
    }
}