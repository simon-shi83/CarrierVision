import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    implicitWidth: 180
    implicitHeight: 36

    // 数字令牌就是轮位；0 表示不筛选，不能回退成驱动轮整组。
    property string selectionToken: "DRIVE"
    readonly property string displayText: selectionToken === "0" ? "全部轮位"
                                      : selectionToken === "DRIVE" ? "全选（驱动轮）"
                                      : selectionToken === "WALK" ? "全选（走行轮）"
                                      : appController.wheelLabel(selectionToken)
    signal selectionChanged(string selectionToken)

    function setSelectionToken(token) {
        var value = String(token).trim()
        selectionToken = (value === "DRIVE" || value === "WALK" || /^([1-9]|1[0-6])$/.test(value)) ? value : "0"
    }

    function select(token) {
        setSelectionToken(token)
        selectionChanged(selectionToken)
        selectorPopup.close()
    }

    function reset() {
        select("DRIVE")
    }

    Button {
        id: selectorButton
        objectName: "wheelSelectorButton"
        anchors.fill: parent
        onClicked: selectorPopup.open()
        contentItem: RowLayout {
            spacing: Theme.space1
            Text {
                text: root.displayText
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontMedium
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            AppIcon {
                name: "icon_arrow_down"
                size: 14
                color: Theme.muted
            }
        }
        background: Rectangle {
            radius: Theme.radiusSmall
            color: selectorButton.hovered ? Theme.hover : Theme.fieldFill
            border.width: 1
            border.color: selectorPopup.visible ? Theme.selectedBorder : Theme.border
        }
        ToolTip.visible: hovered
        ToolTip.text: root.displayText
    }

    Popup {
        id: selectorPopup
        parent: selectorButton
        y: selectorButton.height + Theme.space1
        width: 360
        padding: Theme.space3
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surfaceFloating
            border.color: Theme.border
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: Theme.space2
            ActionButton {
                text: "全部轮位"
                Layout.fillWidth: true
                variant: root.selectionToken === "0" ? "primary" : "secondary"
                onClicked: root.select("0")
            }
            Repeater {
                model: ["WALK", "DRIVE"]
                delegate: ColumnLayout {
                    id: group
                    required property string modelData
                    readonly property bool walking: modelData === "WALK"
                    Layout.fillWidth: true
                    spacing: Theme.space1
                    ActionButton {
                        text: group.walking ? "走行轮全选（轮位1～8）" : "驱动轮全选（轮位9～16）"
                        Layout.fillWidth: true
                        variant: root.selectionToken === group.modelData ? "primary" : "secondary"
                        onClicked: root.select(group.modelData)
                    }
                    RowLayout {
                        spacing: Theme.space1
                        Repeater {
                            model: 8
                            delegate: Button {
                                id: wheelButton
                                objectName: "wheelPosition" + positionNo
                                required property int index
                                readonly property int positionNo: index + (group.walking ? 1 : 9)
                                readonly property string token: String(appController.wheelRawId(positionNo))
                                text: String(positionNo)
                                checkable: true
                                checked: root.selectionToken === token
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                onClicked: root.select(token)
                                contentItem: Text {
                                    text: wheelButton.text
                                    color: wheelButton.checked ? Theme.textOnAccent : Theme.text
                                    font.family: Theme.fontSans
                                    font.features: Theme.fontFeaturesTabular
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.fontMedium
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: Theme.radiusMicro
                                    color: wheelButton.checked ? Theme.accent : (wheelButton.hovered ? Theme.hover : Theme.surface)
                                    border.width: 1
                                    border.color: wheelButton.checked ? Theme.accent : Theme.borderMuted
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: appController.wheelLabel(token)
                            }
                        }
                    }
                }
            }
        }
    }
}
