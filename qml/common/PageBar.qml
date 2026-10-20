import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: bar
    implicitHeight: 52
    enabled: true
    z: 100
    property int currentPage: 1
    property int totalPages: 1
    property int pageSize: 10
    property int totalCount: 0
    property var pageSizeOptions: [10, 20, 50, 100]

    signal pageRequested(int page, int pageSize)
    signal pageSizeSelected(int pageSize)

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.radiusSmall
        border.color: Theme.border
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // 统计总数芯片
            Rectangle {
                Layout.preferredHeight: 30
                implicitWidth: totalText.implicitWidth + 16
                radius: Theme.radiusPill
                color: Theme.surfaceAlt
                border.color: Theme.borderMuted
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        id: totalText
                        text: "共 " + bar.totalCount + " 条记录"
                        color: Theme.textSoft
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.fontMedium
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // 翻页操作组
            RowLayout {
                spacing: 4

                ActionButton {
                    id: btnFirst
                    text: "首页"
                    variant: "secondary"
                    enabled: bar.currentPage > 1
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 32
                    onClicked: {
                        bar.currentPage = 1
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }
                }

                ActionButton {
                    id: btnPrev
                    text: "上一页"
                    variant: "secondary"
                    enabled: bar.currentPage > 1
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 32
                    onClicked: {
                        bar.currentPage--
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }
                }

                // 当前页指示芯片
                Rectangle {
                    Layout.preferredHeight: 32
                    implicitWidth: pageInfoText.implicitWidth + 20
                    radius: Theme.radiusSmall
                    color: Theme.pressed
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        id: pageInfoText
                        anchors.centerIn: parent
                        text: bar.currentPage + " / " + bar.totalPages
                        color: Theme.text
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontBody
                        font.weight: Theme.fontMedium
                    }
                }

                ActionButton {
                    id: btnNext
                    text: "下一页"
                    variant: "secondary"
                    enabled: bar.currentPage < bar.totalPages
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 32
                    onClicked: {
                        bar.currentPage++
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }
                }

                ActionButton {
                    id: btnLast
                    text: "末页"
                    variant: "secondary"
                    enabled: bar.currentPage < bar.totalPages
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 32
                    onClicked: {
                        bar.currentPage = bar.totalPages
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }
                }
            }

            // 分隔线
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                color: Theme.borderMuted
            }

            // 每页数量选择
            RowLayout {
                spacing: 6

                ComboBox {
                    id: cb
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 32
                    model: bar.pageSizeOptions
                    currentIndex: bar.pageSizeOptions.indexOf(bar.pageSize) >= 0 ? bar.pageSizeOptions.indexOf(bar.pageSize) : 0
                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                    font.pixelSize: Theme.fontCaption

                    onCurrentIndexChanged: {
                        bar.pageSize = model[currentIndex]
                        bar.currentPage = 1
                        bar.pageSizeSelected(bar.pageSize)
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.fieldFill
                        border.color: cb.activeFocus ? Theme.selectedBorder : Theme.border
                        border.width: 1
                    }
                    contentItem: Text {
                        text: cb.currentText
                        color: Theme.text
                        font.weight: Theme.fontMedium
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    popup: Popup {
                        y: cb.height + 4
                        width: cb.width
                        implicitHeight: contentItem.implicitHeight + 8
                        padding: 4
                        background: Rectangle {
                            color: Theme.surfaceFloating
                            radius: Theme.radiusSmall
                            border.color: Theme.border
                            border.width: 1
                        }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: cb.popup.visible ? cb.delegateModel : null
                            currentIndex: cb.highlightedIndex
                        }
                    }
                    delegate: ItemDelegate {
                        width: cb.width - 8
                        height: 28
                        contentItem: Text {
                            text: modelData
                            color: Theme.text
                            font.weight: Theme.fontMedium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: Theme.radiusMicro
                            color: highlighted ? Theme.pressed : "transparent"
                        }
                    }
                }

                Text {
                    color: Theme.textSoft
                    text: "条/页"
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
