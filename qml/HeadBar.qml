import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Rectangle {
    id: root
    width: parent ? parent.width : 0
    height: 60
    color: Theme.bgHeader

    // ===== 对外暴露的属性 =====
    property string logoText: "📷"
    property string systemName: "Carrier 自动点检终端系统"
    property color logoColor: Theme.textPrimary
    property color systemNameColor: Theme.textPrimary
    property color timeColor: Theme.primaryLight
    property bool showExitButton: true

    // ===== 信号 =====
    signal exit()

    // 窗口平滑拖拽交互区（双击切换最大化/还原）
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        onPressed: {
            if (Window.window && Window.window.visibility !== Window.Maximized)
                Window.window.startSystemMove()
        }
        onDoubleClicked: {
            if (Window.window) {
                if (Window.window.visibility === Window.Maximized)
                    Window.window.showNormal()
                else
                    Window.window.showMaximized()
            }
        }
    }

    // 底部精细微光分割线
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.borderSubtle
    }

    // ===== 定时器更新时间 =====
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: updateTime()
    }

    function updateTime() {
        var now = new Date()
        var year = now.getFullYear()
        var month = String(now.getMonth() + 1).padStart(2, '0')
        var day = String(now.getDate()).padStart(2, '0')
        dateText.text = year + "-" + month + "-" + day

        var hours = String(now.getHours()).padStart(2, '0')
        var minutes = String(now.getMinutes()).padStart(2, '0')
        var seconds = String(now.getSeconds()).padStart(2, '0')
        timeText.text = hours + ":" + minutes + ":" + seconds
    }

    Component.onCompleted: updateTime()

    // ===== 核心三段式黄金律布局 (左品牌 · 中时钟仪表 · 右控制集群) =====
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        // ==================== 1. 左侧：品牌与系统识别区 ====================
        RowLayout {
            spacing: 12
            Layout.alignment: Qt.AlignVCenter

            // Logo 品牌标识（直接展示，无边框框起，尺寸适度放大）
            Image {
                Layout.preferredHeight: 32
                Layout.preferredWidth: 93
                Layout.alignment: Qt.AlignVCenter
                source: "qrc:/qt/qml/CarrierVision/icons/logo_agc.svg"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 186
                sourceSize.height: 64
                smooth: true
            }

            // 精细垂直分割线
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                color: Theme.borderSubtle
            }

            // 系统名称与状态微胶囊
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    spacing: 8
                    Text {
                        text: root.systemName
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontH2
                        font.weight: Theme.weightBold
                        color: Theme.textPrimary
                    }

                    // 运行状态脉冲药丸徽章
                    Rectangle {
                        Layout.preferredHeight: 18
                        implicitWidth: beaconRow.implicitWidth + 10
                        radius: Theme.radiusPill
                        color: Theme.okBg
                        border.color: Theme.okBorder
                        border.width: 1

                        RowLayout {
                            id: beaconRow
                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.ok

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.3; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }

                            Text {
                                text: "RUNNING"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontMicro
                                font.letterSpacing: Theme.letterSpacingWide
                                font.weight: Theme.weightBold
                                color: Theme.ok
                            }
                        }
                    }
                }

                Text {
                    text: "VISION CONTROL & PRECISION INSPECTION TERMINAL"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontMicro
                    font.letterSpacing: Theme.letterSpacingLoose
                    color: Theme.textMuted
                }
            }
        }

        // ==================== 弹性留白区 1 (Window Drag Spacer) ====================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ==================== 2. 中间：高精工业时钟仪表 (居中平衡) ====================
        Rectangle {
            Layout.preferredHeight: 34
            implicitWidth: 172
            radius: Theme.radiusPill
            color: Theme.bgCardElevated
            border.color: Theme.borderSubtle
            border.width: 1
            Layout.alignment: Qt.AlignVCenter

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    id: timeText
                    text: "12:00:00"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontBodyLarge
                    font.weight: Theme.weightBold
                    color: Theme.primaryLight
                }

                Rectangle {
                    width: 1
                    height: 12
                    color: Theme.divider
                }

                Text {
                    id: dateText
                    text: "2026-09-02"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textSecondary
                }
            }
        }

        // ==================== 弹性留白区 2 (Window Drag Spacer) ====================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ==================== 3. 右侧：功能操作与窗口控制群 ====================
        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            // 昼夜深浅主题切换微按钮
            Rectangle {
                id: themeToggleBtn
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Theme.radiusMd
                color: themeToggleMouse.containsMouse ? Theme.bgCardActive : Theme.bgCardElevated
                border.color: themeToggleMouse.containsMouse ? Theme.borderHover : Theme.borderSubtle
                border.width: 1

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                AppIcon {
                    anchors.centerIn: parent
                    name: Theme.isDark ? "icon_sun" : "icon_moon"
                    size: 15
                    color: themeToggleMouse.containsMouse ? Theme.primaryLight : Theme.textSecondary
                }

                MouseArea {
                    id: themeToggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.toggleTheme()
                }

                ToolTip.visible: themeToggleMouse.containsMouse
                ToolTip.delay: 300
                ToolTip.text: Theme.isDark ? "切换为亮色模式 (Day Mode)" : "切换为暗色模式 (Dark Mode)"
            }

            // 分割线
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                color: Theme.divider
            }

            // 紧凑窗体控制组 (Caption Controls Group)
            RowLayout {
                spacing: 2

                // 最小化
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSm
                    color: winMinMouse.containsMouse ? Theme.bgCardActive : "transparent"

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_win_min"
                        size: 14
                        color: winMinMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        id: winMinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Window.window)
                                Window.window.showMinimized()
                        }
                    }
                    ToolTip.visible: winMinMouse.containsMouse
                    ToolTip.text: "最小化"
                }

                // 最大化 / 还原
                Rectangle {
                    id: winMaxBtn
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSm
                    color: winMaxMouse.containsMouse ? Theme.bgCardActive : "transparent"

                    readonly property bool isMaximized: Window.window && Window.window.visibility === Window.Maximized

                    AppIcon {
                        anchors.centerIn: parent
                        name: winMaxBtn.isMaximized ? "icon_win_restore" : "icon_win_max"
                        size: 14
                        color: winMaxMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        id: winMaxMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Window.window) {
                                if (winMaxBtn.isMaximized)
                                    Window.window.showNormal()
                                else
                                    Window.window.showMaximized()
                            }
                        }
                    }
                    ToolTip.visible: winMaxMouse.containsMouse
                    ToolTip.text: winMaxBtn.isMaximized ? "还原视窗" : "最大化"
                }

                // 关闭系统按钮
                Rectangle {
                    id: winCloseBtn
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSm
                    color: winCloseMouse.containsMouse ? Theme.ngBg : "transparent"

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_close"
                        size: 14
                        color: winCloseMouse.containsMouse ? Theme.ng : Theme.textSecondary
                    }

                    MouseArea {
                        id: winCloseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.exit()
                    }
                    ToolTip.visible: winCloseMouse.containsMouse
                    ToolTip.text: "关闭系统"
                }
            }
        }
    }
}