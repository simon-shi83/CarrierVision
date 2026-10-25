import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ============ 工业精密度 Red Dot 架号选择器 ============
Rectangle {
    id: numberPicker
    width: parent ? parent.width : 76
    height: parent ? parent.height : 36
    color: Theme.fieldFill
    radius: Theme.radiusSmall
    border.color: popup.visible ? Theme.selectedBorder : Theme.border
    border.width: 1

    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    property int selectedValue: 0
    property string valueText: ""
    property string theme: "dark"
    property string labelText: ""
    property bool showAllButton: true

    signal valueChanged(int value)

    property int _selected: 0

    function getValue() {
        return _selected
    }

    function setValue(value) {
        _selected = value
        selectedValue = value
        valueText = value === 0 ? "全部" : value.toString()
        valueChanged(value)
        popup.visible = false
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Text {
            text: labelText
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontCaption
            font.weight: Theme.fontMedium
            color: Theme.textSoft
            visible: labelText !== ""
            Layout.preferredWidth: visible ? implicitWidth : 0
        }

        Text {
            id: displayText
            text: valueText
            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontMedium
            color: _selected === 0 ? Theme.textSoft : Theme.text
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        AppIcon {
            name: "icon_arrow_down"
            size: 14
            color: Theme.muted
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            popup.visible = !popup.visible
        }
    }

    Popup {
        id: popup
        x: 0
        y: numberPicker.height + 4
        width: 320
        height: 250
        padding: 0
        modal: false
        closePolicy: Popup.CloseOnPressOutside
        z: 100

        background: Rectangle {
            color: Theme.surfaceFloating
            radius: Theme.radiusSmall
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            id: colLayout
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Rectangle {
                visible: numberPicker.showAllButton
                Layout.fillWidth: visible
                Layout.preferredHeight: visible ? 30 : 0
                color: {
                    if (_selected === 0) return Theme.accent
                    if (allMouse.containsMouse) return Theme.pressed
                    return "transparent"
                }
                radius: Theme.radiusMicro
                border.color: _selected === 0 ? Theme.accent : Theme.borderMuted
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "全部架号"
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontBody
                    font.weight: Theme.fontMedium
                    color: _selected === 0 ? Theme.textOnAccent : Theme.textSoft
                }

                MouseArea {
                    id: allMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        setValue(0)
                    }
                }
            }

            Repeater {
                id: rowRepeater
                model: 5

                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Repeater {
                        id: colRepeater
                        model: 10

                        property int startValue: index * 10 + 1

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            property int numValue: colRepeater.startValue + model.index
                            color: {
                                if (numValue === _selected) return Theme.accent
                                if (numMouse.containsMouse) return Theme.pressed
                                return Theme.surface
                            }
                            radius: Theme.radiusMicro
                            border.color: numValue === _selected ? Theme.accent : Theme.borderMuted
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: numValue
                                font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                                font.pixelSize: Theme.fontCaption
                                font.weight: (numValue === _selected) ? Theme.fontMedium : Theme.fontRegular
                                color: numValue === _selected ? Theme.textOnAccent : Theme.text
                            }

                            MouseArea {
                                id: numMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    setValue(numValue)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onSelectedValueChanged: {
        if (_selected !== selectedValue) {
            _selected = selectedValue
            valueText = selectedValue === 0 ? "全部" : selectedValue.toString()
        }
    }

    Component.onCompleted: {
        if (showAllButton) {
            _selected = 0
            selectedValue = 0
            valueText = "全部"
        } else {
            const initialValue = selectedValue > 0 ? selectedValue : 1
            _selected = initialValue
            selectedValue = initialValue
            valueText = initialValue.toString()
        }
    }
}