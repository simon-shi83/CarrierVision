import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    implicitWidth: 130
    implicitHeight: 36

    property string selectionToken: "DRIVE"
    readonly property string displayText: selectionToken === "DRIVE" ? "全选 (驱动轮)"
                                      : selectionToken === "WALK" ? "全选 (走行轮)"
                                      : "轮位 " + selectionToken
    signal selectionChanged(string selectionToken)

    function select(token) {
        selectionToken = String(token)
        selectionChanged(selectionToken)
        selectorPopup.close()
    }

    function setSelectionToken(token) {
        var value = String(token).trim()
        selectionToken = (value === "DRIVE" || value === "WALK" || /^([1-9]|1[0-6])$/.test(value)) ? value : "DRIVE"
    }

    function reset() {
        selectionToken = "DRIVE"
        selectionChanged(selectionToken)
    }

    Button {
        id: selectorButton
        anchors.fill: parent
        onClicked: selectorPopup.open()
        
        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: root.displayText
                color: root.selectionToken === "WALK" || Number(root.selectionToken) >= 9 ? Theme.walkWheel : Theme.driveWheel
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontBody
                font.weight: Theme.fontMedium
                elide: Text.ElideRight
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
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
        }
    }

    Popup {
        id: selectorPopup
        parent: selectorButton
        x: 0
        y: selectorButton.height + 4
        width: 340
        padding: 12
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { 
            radius: Theme.radiusSmall 
            color: Theme.surfaceFloating 
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            // 驱动轮标题与全选
            Button {
                text: "驱动轮全选 (轮 1 ~ 8)"
                Layout.fillWidth: true
                checkable: true
                checked: root.selectionToken === "DRIVE"
                onClicked: root.select("DRIVE")
                contentItem: Text { 
                    text: parent.text
                    color: parent.checked ? Theme.textOnAccent : Theme.driveWheel
                    font.family: Theme.fontSans
                    font.weight: Theme.fontMedium
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                }
                background: Rectangle {
                    radius: Theme.radiusMicro
                    color: parent.checked ? Theme.driveWheel : (parent.hovered ? Theme.driveWheelSoft : Theme.surface)
                    border.width: 1
                    border.color: parent.checked ? Theme.driveWheel : Theme.borderMuted
                }
            }
            
            RowLayout {
                spacing: 4
                Repeater {
                    model: 8
                    delegate: Button {
                        required property int index
                        property string token: String(index + 1)
                        text: token
                        checkable: true
                        checked: root.selectionToken === token
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        onClicked: root.select(token)
                        contentItem: Text { 
                            text: parent.text 
                            color: parent.checked ? Theme.textOnAccent : Theme.text
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.weight: Theme.fontMedium
                            horizontalAlignment: Text.AlignHCenter 
                            verticalAlignment: Text.AlignVCenter 
                        }
                        background: Rectangle {
                            radius: Theme.radiusMicro
                            color: parent.checked ? Theme.driveWheel : (parent.hovered ? Theme.pressed : Theme.surface)
                            border.width: 1
                            border.color: parent.checked ? Theme.driveWheel : Theme.borderMuted
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderMuted
            }

            // 走行轮标题与全选
            Button {
                text: "走行轮全选 (轮 9 ~ 16)"
                Layout.fillWidth: true
                checkable: true
                checked: root.selectionToken === "WALK"
                onClicked: root.select("WALK")
                contentItem: Text { 
                    text: parent.text
                    color: parent.checked ? Theme.textOnAccent : Theme.walkWheel
                    font.family: Theme.fontSans
                    font.weight: Theme.fontMedium
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                }
                background: Rectangle {
                    radius: Theme.radiusMicro
                    color: parent.checked ? Theme.walkWheel : (parent.hovered ? Theme.walkWheelSoft : Theme.surface)
                    border.width: 1
                    border.color: parent.checked ? Theme.walkWheel : Theme.borderMuted
                }
            }

            RowLayout {
                spacing: 4
                Repeater {
                    model: 8
                    delegate: Button {
                        required property int index
                        property string token: String(index + 9)
                        text: token
                        checkable: true
                        checked: root.selectionToken === token
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        onClicked: root.select(token)
                        contentItem: Text { 
                            text: parent.text 
                            color: parent.checked ? Theme.textOnAccent : Theme.text
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.weight: Theme.fontMedium
                            horizontalAlignment: Text.AlignHCenter 
                            verticalAlignment: Text.AlignVCenter 
                        }
                        background: Rectangle {
                            radius: Theme.radiusMicro
                            color: parent.checked ? Theme.walkWheel : (parent.hovered ? Theme.pressed : Theme.surface)
                            border.width: 1
                            border.color: parent.checked ? Theme.walkWheel : Theme.borderMuted
                        }
                    }
                }
            }
        }
    }
}
