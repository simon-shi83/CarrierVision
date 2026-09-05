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
        color: Theme.bgCard
        radius: Theme.radiusMd
        border.color: Theme.borderMedium
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
                color: Theme.bgCardElevated
                border.color: Theme.borderSubtle
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "●"
                        color: Theme.primaryLight
                        font.pixelSize: 8
                    }
                    Text {
                        id: totalText
                        text: "共 " + bar.totalCount + " 条记录"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
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
                    radius: Theme.radiusMd
                    color: Theme.bgCardActive
                    border.color: Theme.borderMedium
                    border.width: 1

                    Text {
                        id: pageInfoText
                        anchors.centerIn: parent
                        text: bar.currentPage + " / " + bar.totalPages
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
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
                color: Theme.divider
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
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSmall

                    onCurrentIndexChanged: {
                        bar.pageSize = model[currentIndex]
                        bar.currentPage = 1
                        bar.pageSizeSelected(bar.pageSize)
                        bar.pageRequested(bar.currentPage, bar.pageSize)
                    }

                    background: Rectangle {
                        radius: Theme.radiusMd
                        color: Theme.bgInput
                        border.color: cb.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                        border.width: 1
                    }
                    contentItem: Text {
                        text: cb.currentText
                        color: Theme.textPrimary
                        font.bold: true
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    popup: Popup {
                        y: cb.height + 4
                        width: cb.width
                        implicitHeight: contentItem.implicitHeight + 8
                        padding: 4
                        background: Rectangle {
                            color: Theme.bgPopup
                            radius: Theme.radiusMd
                            border.color: Theme.borderMedium
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
                            color: Theme.textPrimary
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: highlighted ? Theme.bgCardActive : "transparent"
                        }
                    }
                }

                Text {
                    color: Theme.textSecondary
                    text: "条/页"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
