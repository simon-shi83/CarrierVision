import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle { width: 4; height: 18; radius: 2; color: Theme.borderStrong }

                Label {
                    text: "统计周报历史归档一览"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontTitle
                    font.weight: Theme.fontMedium
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 22
                    implicitWidth: reportHintRow.implicitWidth + 14
                    radius: Theme.radiusPill
                    color: Theme.surfaceAlt
                    border.color: Theme.borderMuted
                    border.width: 1

                    RowLayout {
                        id: reportHintRow
                        anchors.centerIn: parent
                        spacing: 4
                        AppIcon { name: "icon_file_text"; size: 11; color: Theme.muted }
                        Text {
                            text: "支持轻触或双击文件直接调取打开"
                            color: Theme.muted
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontMicro
                        }
                    }
                }
            }

            // 表头
            Rectangle {
                Layout.fillWidth: true
                height: 38
                color: Theme.surfaceAlt
                radius: Theme.radiusSmall
                border.color: Theme.borderMuted
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Text { text: "生成归档时间"; font.family: Theme.fontSans; font.weight: Theme.fontMedium; color: Theme.textSoft; Layout.preferredWidth: 200 }
                    Text { text: "驱动轮周报报表文件"; font.family: Theme.fontSans; font.weight: Theme.fontMedium; color: Theme.driveWheel; Layout.fillWidth: true }
                    Text { text: "走行轮周报报表文件"; font.family: Theme.fontSans; font.weight: Theme.fontMedium; color: Theme.walkWheel; Layout.fillWidth: true }
                }
            }

            // 列表
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: ListModel { id: listModel }
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: listView.width
                    height: 48
                    radius: Theme.radiusSmall
                    color: itemMouse.containsMouse ? Theme.pressed : ((index % 2 === 0) ? Theme.fieldFill : "transparent")
                    border.width: 1
                    border.color: itemMouse.containsMouse ? Theme.border : "transparent"

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text {
                            text: model.createtime
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.pixelSize: Theme.fontBody
                            color: Theme.text
                            Layout.preferredWidth: 200
                        }

                        // 驱动轮报表芯片
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Theme.radiusMicro
                            color: driverMouse.containsMouse ? Theme.driveWheelSoft : Theme.surfaceAlt
                            border.color: driverMouse.containsMouse ? Theme.driveWheel : Theme.borderMuted
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                AppIcon {
                                    name: "icon_file_text"
                                    size: 14
                                    color: driverMouse.containsMouse ? Theme.driveWheel : Theme.muted
                                }

                                Text {
                                    id: driversFileText
                                    text: model.drivers_filename
                                    color: driverMouse.containsMouse ? Theme.driveWheel : Theme.textSoft
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontCaption
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "打开"
                                    color: Theme.driveWheel
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontMicro
                                    font.weight: Theme.fontMedium
                                    visible: driverMouse.containsMouse
                                }
                            }

                            MouseArea {
                                id: driverMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (appController && appController.openReportFile)
                                        appController.openReportFile(driversFileText.text)
                                }
                                onDoubleClicked: {
                                    if (appController && appController.openReportFile)
                                        appController.openReportFile(driversFileText.text)
                                }
                            }
                        }

                        // 走行轮报表芯片
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Theme.radiusMicro
                            color: deformMouse.containsMouse ? Theme.walkWheelSoft : Theme.surfaceAlt
                            border.color: deformMouse.containsMouse ? Theme.walkWheel : Theme.borderMuted
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                AppIcon {
                                    name: "icon_file_text"
                                    size: 14
                                    color: deformMouse.containsMouse ? Theme.walkWheel : Theme.muted
                                }

                                Text {
                                    id: deformedFileText
                                    text: model.deformed_filename
                                    color: deformMouse.containsMouse ? Theme.walkWheel : Theme.textSoft
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontCaption
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "打开"
                                    color: Theme.walkWheel
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontMicro
                                    font.weight: Theme.fontMedium
                                    visible: deformMouse.containsMouse
                                }
                            }

                            MouseArea {
                                id: deformMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (appController && appController.openReportFile)
                                        appController.openReportFile(deformedFileText.text)
                                }
                                onDoubleClicked: {
                                    if (appController && appController.openReportFile)
                                        appController.openReportFile(deformedFileText.text)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: listModel.count === 0
                    color: "transparent"
                    ColumnLayout {
                        spacing: 8
                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            name: "icon_file_text"
                            size: 36
                            color: Theme.muted
                            opacity: 0.35
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "暂无周报归档记录"
                            color: Theme.muted
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        listModel.clear()
        if (appController && appController.weeklyReports) {
            var reports = appController.weeklyReports()
            for (var i = 0; i < reports.length; ++i) {
                listModel.append(reports[i])
            }
        }
    }
}
