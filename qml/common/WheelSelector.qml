import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    implicitWidth: 130
    implicitHeight: 36

    property string selectionToken: "0"
    readonly property string displayText: selectionToken === "0" ? "全选 (驱动轮)"
                                      : selectionToken === "10" ? "全选 (走行轮)"
                                      : "轮位 " + selectionToken
    signal selectionChanged(string selectionToken)

    function select(token) {
        selectionToken = String(token)
        selectionChanged(selectionToken)
        selectorPopup.close()
    }

    function setSelectionToken(token) {
        var value = String(token).trim()
        selectionToken = value === "10" || value === "0" || /^([1-8]|1[1-8])$/.test(value) ? value : "0"
    }

    function reset() {
        selectionToken = "0"
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
                color: root.selectionToken === "10" || Number(root.selectionToken) >= 11 ? Theme.walkWheel : Theme.driveWheel
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: "▾"
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }
        
        background: Rectangle {
            radius: Theme.radiusMd
            color: selectorButton.hovered ? Theme.bgInputHover : Theme.bgInput
            border.width: 1
            border.color: selectorPopup.visible ? Theme.borderHighlight : Theme.borderMedium
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
            radius: Theme.radiusMd 
            color: Theme.bgPopup 
            border.color: Theme.borderMedium
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            // 驱动轮标题与全选
            Button {
                text: "驱动轮全选 (轮 1 ~ 8)"
                Layout.fillWidth: true
                checkable: true
                checked: root.selectionToken === "0"
                onClicked: root.select("0")
                contentItem: Text { 
                    text: parent.text
                    color: parent.checked ? "#ffffff" : Theme.driveWheel
                    font.family: Theme.fontFamily
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                }
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: parent.checked ? Theme.driveWheel : (parent.hovered ? Theme.driveWheelBg : Theme.bgCard)
                    border.width: 1
                    border.color: parent.checked ? Theme.driveWheel : Theme.borderSubtle
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
                            color: parent.checked ? "#ffffff" : Theme.textPrimary
                            font.family: Theme.fontMono
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter 
                            verticalAlignment: Text.AlignVCenter 
                        }
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: parent.checked ? Theme.driveWheel : (parent.hovered ? Theme.bgCardActive : Theme.bgCard)
                            border.width: 1
                            border.color: parent.checked ? Theme.driveWheel : Theme.borderSubtle
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.divider
            }

            // 走行轮标题与全选
            Button {
                text: "走行轮全选 (轮 11 ~ 18)"
                Layout.fillWidth: true
                checkable: true
                checked: root.selectionToken === "10"
                onClicked: root.select("10")
                contentItem: Text { 
                    text: parent.text
                    color: parent.checked ? "#ffffff" : Theme.walkWheel
                    font.family: Theme.fontFamily
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                }
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: parent.checked ? Theme.walkWheel : (parent.hovered ? Theme.walkWheelBg : Theme.bgCard)
                    border.width: 1
                    border.color: parent.checked ? Theme.walkWheel : Theme.borderSubtle
                }
            }

            RowLayout {
                spacing: 4
                Repeater {
                    model: 8
                    delegate: Button {
                        required property int index
                        property string token: String(index + 11)
                        text: token
                        checkable: true
                        checked: root.selectionToken === token
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        onClicked: root.select(token)
                        contentItem: Text { 
                            text: parent.text 
                            color: parent.checked ? "#ffffff" : Theme.textPrimary
                            font.family: Theme.fontMono
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter 
                            verticalAlignment: Text.AlignVCenter 
                        }
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: parent.checked ? Theme.walkWheel : (parent.hovered ? Theme.bgCardActive : Theme.bgCard)
                            border.width: 1
                            border.color: parent.checked ? Theme.walkWheel : Theme.borderSubtle
                        }
                    }
                }
            }
        }
    }
}
