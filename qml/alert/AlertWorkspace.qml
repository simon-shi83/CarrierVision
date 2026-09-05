import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Item {
    id: root
    anchors.fill: parent

    // ========== 报警中心二级导航 ==========
    property var menuData: [
        {
            title: "异常记录",
            iconName: "icon_file_text",
            iconText: "📑",
            pageSource: "AlertRecordPage.qml",
            enabled: true
        },
        {
            title: "报警统计",
            iconName: "icon_chart_bar",
            iconText: "📊",
            pageSource: "AlertStatsPage.qml",
            enabled: true
        }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 10

        // 左侧二级导航 (内联垂直菜单)
        Rectangle {
            id: navMenu
            Layout.preferredWidth: 88
            Layout.fillHeight: true
            color: Theme.bgNav
            radius: Theme.radiusMd

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 1
                color: Theme.borderSubtle
            }

            property int currentIndex: 0

            ListView {
                id: navListView
                anchors.fill: parent
                anchors.margins: 6
                orientation: ListView.Vertical
                model: root.menuData
                currentIndex: navMenu.currentIndex
                spacing: 6
                interactive: false

                delegate: Item {
                    id: delegateRoot
                    required property var modelData
                    required property int index

                    width: navListView.width
                    height: 58

                    readonly property bool isDisabled: delegateRoot.modelData ? (delegateRoot.modelData.enabled === false) : false
                    readonly property bool isHovered: mouseArea.containsMouse && !isDisabled
                    readonly property bool isSelected: delegateRoot.index === navMenu.currentIndex && !isDisabled
                    readonly property string itemIconName: (delegateRoot.modelData && delegateRoot.modelData.iconName) ? String(delegateRoot.modelData.iconName) : ""

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMd
                        color: delegateRoot.isSelected ? Theme.bgCardActive : (delegateRoot.isHovered ? Theme.bgCardElevated : "transparent")

                        border.width: 1
                        border.color: delegateRoot.isSelected ? Theme.primary : (delegateRoot.isHovered ? Theme.borderMedium : "transparent")

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.animFast
                            }
                        }
                        Behavior on border.color {
                            ColorAnimation {
                                duration: Theme.animFast
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: delegateRoot.isSelected ? parent.height - 18 : 0
                            radius: 2
                            color: Theme.primaryLight
                            visible: delegateRoot.isSelected
                            Behavior on height {
                                NumberAnimation {
                                    duration: Theme.animNormal
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            AppIcon {
                                visible: delegateRoot.itemIconName !== ""
                                name: delegateRoot.itemIconName
                                size: 18
                                color: delegateRoot.isSelected ? Theme.primaryLight : (delegateRoot.isHovered ? Theme.textPrimary : Theme.textSecondary)
                                Layout.alignment: Qt.AlignHCenter
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }

                            Text {
                                visible: delegateRoot.itemIconName === ""
                                text: (delegateRoot.modelData && delegateRoot.modelData.iconText) ? delegateRoot.modelData.iconText : "●"
                                font.pixelSize: 18
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignHCenter
                                color: delegateRoot.isSelected ? Theme.primaryLight : (delegateRoot.isHovered ? Theme.textPrimary : Theme.textSecondary)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }

                            Text {
                                text: (delegateRoot.modelData && delegateRoot.modelData.title) ? delegateRoot.modelData.title : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: delegateRoot.isSelected
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignHCenter
                                color: delegateRoot.isSelected ? Theme.primaryLight : (delegateRoot.isHovered ? Theme.textPrimary : Theme.textSecondary)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: delegateRoot.isDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !delegateRoot.isDisabled

                            onClicked: {
                                navMenu.currentIndex = delegateRoot.index;
                                if (delegateRoot.modelData && delegateRoot.modelData.pageSource) {
                                    contentLoader.source = delegateRoot.modelData.pageSource;
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            Loader {
                id: contentLoader
                anchors.fill: parent
                source: (root.menuData && root.menuData.length > 0) ? root.menuData[0].pageSource : "AlertRecordPage.qml"
            }
        }
    }
}
