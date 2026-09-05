import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Item {
    id: root
    anchors.fill: parent

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Item {
            width: parent.width
            implicitHeight: mainCol.implicitHeight + 40

            ColumnLayout {
                id: mainCol
                width: Math.min(860, parent.width - 64)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 16
                spacing: 16

                // ==================== 1. 系统主页与视觉偏好 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: descCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: descCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "系统常规与显示偏好"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "支持定制主页左上角展示的标语与界面视觉模式"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        // 主页描述多行输入
                        TextArea {
                            id: descriptionInput
                            Layout.fillWidth: true
                            Layout.preferredHeight: 68
                            text: appController ? appController.homepageDescription : ""
                            placeholderText: "请输入系统主页展示的说明信息..."
                            placeholderTextColor: Theme.textMuted
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap

                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: Theme.bgInput
                                border.width: 1
                                border.color: descriptionInput.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                Layout.preferredWidth: 84
                                Layout.preferredHeight: 32
                                text: "保存描述"
                                variant: "primary"
                                onClicked: {
                                    if (appController && appController.saveHomepageDescription(descriptionInput.text))
                                        descriptionInput.text = appController.homepageDescription
                                }
                            }
                        }

                        // 视觉主题切换栏
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            color: Theme.bgInput
                            radius: Theme.radiusSm
                            border.width: 1
                            border.color: Theme.borderSubtle

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                AppIcon {
                                    name: Theme.isDark ? "icon_moon" : "icon_sun"
                                    size: 18
                                    color: Theme.primaryLight
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Text {
                                        text: "界面视觉模式"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontBody
                                        font.weight: Theme.weightMedium
                                    }
                                    Text {
                                        text: Theme.isDark ? "当前为【极夜冷黑】工业主题 (适配车间暗光与高对比度巡检)" : "当前为【简约清晰】明亮主题 (适配日间光照良好工位)"
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                ActionButton {
                                    text: Theme.isDark ? "切换为亮色模式" : "切换为暗色模式"
                                    variant: "secondary"
                                    Layout.preferredWidth: 110
                                    Layout.preferredHeight: 28
                                    onClicked: Theme.toggleTheme()
                                }
                            }
                        }
                    }
                }

                // ==================== 2. 工位相机通道映射配置 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: slotCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: slotCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // 标题行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "工位相机通道映射配置"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "配置物理工业相机采集通道 (1~12) 映射至显示槽位 (Slot 1~12)"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        // 12 通道相机网格 (4列 x 3行)
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: 8
                            columnSpacing: 8

                            Repeater {
                                model: 12

                                delegate: Rectangle {
                                    id: camItem
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 52
                                    radius: Theme.radiusSm
                                    color: Theme.bgInput
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    readonly property int camNumber: index + 1
                                    readonly property int currentSlot: {
                                        if (appController && appController.slotMapping && appController.slotMapping.length > index) {
                                            var val = Number(appController.slotMapping[index]);
                                            return (val >= 1 && val <= 14) ? val : camNumber;
                                        }
                                        return camNumber;
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        // 相机序号指示块
                                        Rectangle {
                                            Layout.preferredWidth: 30
                                            Layout.preferredHeight: 30
                                            radius: Theme.radiusSm
                                            color: Theme.primaryGlow
                                            border.color: Theme.primary
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: (camItem.camNumber < 10 ? "0" : "") + camItem.camNumber
                                                color: Theme.primaryLight
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontCaption
                                                font.weight: Theme.weightBold
                                            }
                                        }

                                        // 相机标签
                                        Text {
                                            text: "CAM" + camItem.camNumber
                                            color: Theme.textPrimary
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontBody
                                            font.weight: Theme.weightMedium
                                        }

                                        Text {
                                            text: "→"
                                            color: Theme.textMuted
                                            font.pixelSize: Theme.fontCaption
                                        }

                                        // 槽位选择下拉框
                                        ComboBox {
                                            id: slotCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            model: [
                                                "槽位 01", "槽位 02", "槽位 03", "槽位 04",
                                                "槽位 05", "槽位 06", "槽位 07", "槽位 08",
                                                "槽位 09", "槽位 10", "槽位 11", "槽位 12"
                                            ]
                                            currentIndex: Math.max(0, Math.min(11, camItem.currentSlot - 1))
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontBody

                                            background: Rectangle {
                                                color: slotCombo.hovered ? Theme.bgCardElevated : Theme.bgCard
                                                radius: Theme.radiusSm
                                                border.color: slotCombo.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                                                border.width: 1
                                            }

                                            contentItem: Text {
                                                text: slotCombo.currentText
                                                color: Theme.textPrimary
                                                font: slotCombo.font
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 8
                                            }

                                            onActivated: {
                                                if (appController) {
                                                    appController.setSlotMapping(camItem.camNumber, currentIndex + 1);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 底部操作与说明
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "💡 提示: 若现场布线或网口物理顺序发生调整，直接修改对应槽位即可即时生效"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }

                            Item { Layout.fillWidth: true }

                            ActionButton {
                                Layout.preferredWidth: 108
                                Layout.preferredHeight: 28
                                text: "恢复默认 (1:1)"
                                variant: "secondary"
                                onClicked: {
                                    if (appController) appController.resetSlotMapping()
                                }
                            }
                        }
                    }
                }

                // ==================== 3. TCP 点检通信服务管理 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tcpCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: tcpCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // 标题与运行状态徽章
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "TCP 点检通信服务管理"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: 24
                                implicitWidth: tcpStatusText.implicitWidth + 20
                                radius: Theme.radiusPill
                                color: (appController && appController.serverRunning) ? Theme.okBg : Theme.ngBg
                                border.color: (appController && appController.serverRunning) ? Theme.okBorder : Theme.ngBorder
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: (appController && appController.serverRunning) ? Theme.ok : Theme.ng
                                    }
                                    Text {
                                        id: tcpStatusText
                                        text: (appController && appController.serverRunning) ? "TCP 监听中" : "服务已停止"
                                        color: (appController && appController.serverRunning) ? Theme.okLight : Theme.ngLight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                    }
                                }
                            }
                        }

                        // 端口配置与启停控制
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: "监听端口:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                            }

                            TextField {
                                id: tcpPortInput
                                text: appController ? String(appController.listenPort) : "22345"
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: tcpPortInput.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }

                            ActionButton {
                                text: "保存端口"
                                variant: "secondary"
                                Layout.preferredWidth: 78
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) {
                                        appController.setListenPort(Number(tcpPortInput.text))
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            ActionButton {
                                text: (appController && appController.serverRunning) ? "停止服务" : "启动服务"
                                variant: (appController && appController.serverRunning) ? "danger" : "success"
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) {
                                        if (appController.serverRunning) appController.stopTcpServer()
                                        else appController.startTcpServer()
                                    }
                                }
                            }
                        }

                        // 实时报文状态栏
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: Theme.radiusSm
                            color: Theme.bgInput
                            border.width: 1
                            border.color: Theme.borderSubtle

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: "最近接收点检报文:"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontCaption
                                    font.weight: Theme.weightMedium
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (appController && appController.lastTcpMessage && appController.lastTcpMessage.length > 0)
                                          ? appController.lastTcpMessage
                                          : "暂无点检信号 (等待外部 PLC/控制终端发送)"
                                    color: (appController && appController.lastTcpMessage && appController.lastTcpMessage.length > 0)
                                           ? Theme.okLight : Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontBody
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: "协议: [架号,轮号,累计数]"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontCaption
                                }
                            }
                        }
                    }
                }

                // ==================== 4. FTP 传输服务管理 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ftpCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: ftpCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // 标题与运行状态徽章
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "FTP 传输服务管理"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: 24
                                implicitWidth: statusText.implicitWidth + 20
                                radius: Theme.radiusPill
                                color: (appController && appController.ftpRunning) ? Theme.okBg : Theme.ngBg
                                border.color: (appController && appController.ftpRunning) ? Theme.okBorder : Theme.ngBorder
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: (appController && appController.ftpRunning) ? Theme.ok : Theme.ng
                                    }
                                    Text {
                                        id: statusText
                                        text: (appController && appController.ftpRunning) ? "服务运行中" : "服务已停止"
                                        color: (appController && appController.ftpRunning) ? Theme.okLight : Theme.ngLight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaption
                                        font.weight: Theme.weightMedium
                                    }
                                }
                            }
                        }

                        // FTP 存储根目录
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: "存储根目录:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 80
                            }

                            TextField {
                                id: ftpRootInput
                                text: appController ? (appController.ftpRoot ? appController.ftpRoot : appController.archiveDirectory) : ""
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: ftpRootInput.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }

                            ActionButton {
                                text: "保存路径"
                                variant: "secondary"
                                Layout.preferredWidth: 78
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController && ftpRootInput.text.length > 0) {
                                        appController.setFtpRoot(ftpRootInput.text)
                                    }
                                }
                            }

                            ActionButton {
                                text: "打开目录"
                                variant: "secondary"
                                Layout.preferredWidth: 78
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) appController.openFtpRootDirectory()
                                }
                            }
                        }

                        // 添加账户行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            TextField {
                                id: newUser
                                placeholderText: "新用户名"
                                placeholderTextColor: Theme.textMuted
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: newUser.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }

                            TextField {
                                id: newPass
                                placeholderText: "密码"
                                placeholderTextColor: Theme.textMuted
                                echoMode: TextInput.Password
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: newPass.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }

                            ActionButton {
                                text: "添加账户"
                                variant: "primary"
                                Layout.preferredWidth: 84
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController && newUser.text.length > 0) {
                                        appController.addFtpAccount(newUser.text, newPass.text)
                                        newUser.text = ""
                                        newPass.text = ""
                                    }
                                }
                            }
                        }

                        // 账户列表
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(80, Math.min(180, accountsList.count * 38 + 10))
                            color: Theme.bgInput
                            radius: Theme.radiusSm
                            border.width: 1
                            border.color: Theme.borderSubtle
                            clip: true

                            ListView {
                                id: accountsList
                                anchors.fill: parent
                                anchors.margins: 4
                                model: appController ? appController.ftpAccounts : []
                                spacing: 3

                                delegate: Rectangle {
                                    width: accountsList.width
                                    height: 34
                                    radius: Theme.radiusSm
                                    color: itemMouse.containsMouse ? Theme.bgCardActive : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        RowLayout {
                                            Layout.preferredWidth: 160
                                            spacing: 6
                                            AppIcon {
                                                name: "icon_user"
                                                size: 14
                                                color: Theme.primaryLight
                                            }
                                            Text {
                                                text: modelData.user
                                                color: Theme.textPrimary
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontBody
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: modelData.hasPassword ? "••••••••" : "(无密码)"
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontBody
                                            Layout.fillWidth: true
                                        }

                                        Button {
                                            text: "删除"
                                            Layout.preferredWidth: 50
                                            Layout.preferredHeight: 24
                                            onClicked: appController && appController.removeFtpAccount(modelData.user)
                                            contentItem: Text {
                                                text: parent.text
                                                color: Theme.ngLight
                                                font.pixelSize: Theme.fontCaption
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                radius: Theme.radiusSm
                                                color: parent.hovered ? Theme.ngBg : "transparent"
                                                border.color: Theme.ngBorder
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }
                                }
                            }

                            // 空账户提示
                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: accountsList.count === 0
                                spacing: 4
                                AppIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    name: "icon_user"
                                    size: 24
                                    color: Theme.textMuted
                                    opacity: 0.4
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "暂无 FTP 访问账户，请在上方添加"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontCaption
                                }
                            }
                        }

                        // 端口配置与服务开关
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: "监听端口:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                            }

                            TextField {
                                id: rootFtpPort
                                text: appController ? String(appController.ftpPort) : "21"
                                Layout.preferredWidth: 68
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: rootFtpPort.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }

                            ActionButton {
                                text: "保存端口"
                                variant: "secondary"
                                Layout.preferredWidth: 78
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) {
                                        appController.setFtpPort(Number(rootFtpPort.text))
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            ActionButton {
                                text: (appController && appController.ftpRunning) ? "停止服务" : "启动服务"
                                variant: (appController && appController.ftpRunning) ? "danger" : "success"
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) {
                                        if (appController.ftpRunning) appController.stopFtpServer()
                                        else appController.startFtpServer()
                                    }
                                }
                            }
                        }
                    }
                }

                // ==================== 5. 系统数据与存储路径管理 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: storageCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: storageCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "系统数据与存储路径管理"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "查看本地图像归档及运行日志的实际存储路径"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        // 历史图像归档目录
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: "图像归档目录:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 96
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.bgInput
                                radius: Theme.radiusSm
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: Text.AlignVCenter
                                    text: appController ? appController.archiveDirectory : ""
                                    color: Theme.textPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontBody
                                    elide: Text.ElideMiddle
                                }
                            }

                            ActionButton {
                                text: "打开归档目录"
                                variant: "secondary"
                                Layout.preferredWidth: 96
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) appController.openArchiveDirectory()
                                }
                            }
                        }

                        // 系统运行日志目录
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: "系统运行日志:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 96
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.bgInput
                                radius: Theme.radiusSm
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: Text.AlignVCenter
                                    text: "logs/ 目录 (每日按日期轮转归档，支持追溯排查)"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBody
                                    elide: Text.ElideRight
                                }
                            }

                            ActionButton {
                                text: "打开日志目录"
                                variant: "secondary"
                                Layout.preferredWidth: 96
                                Layout.preferredHeight: 32
                                onClicked: {
                                    if (appController) appController.openLogDirectory()
                                }
                            }
                        }
                    }
                }

                // ==================== 6. 磁盘与历史数据自动清理 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: cleanCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        id: cleanCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // 标题行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.warning }
                            Label {
                                text: "磁盘与历史数据自动清理"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "系统每日定时扫描，超期图像与日志自动删除"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        // 参数配置卡片组 (图像保留期限 + 日志保留期限)
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 12

                            // 1. 图像保留期限
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 80
                                radius: Theme.radiusSm
                                color: Theme.bgInput
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "🖼️ 图像保留期限:"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontBody
                                            font.weight: Theme.weightMedium
                                        }
                                        Item { Layout.fillWidth: true }
                                        SpinBox {
                                            id: imageKeepDaysBox
                                            Layout.preferredWidth: 96
                                            Layout.preferredHeight: 28
                                            from: 1
                                            to: 3650
                                            value: appController ? appController.cleanupKeepDays() : 90
                                            onValueChanged: {
                                                if (appController) appController.setCleanupKeepDays(value)
                                            }
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontBody
                                            background: Rectangle {
                                                radius: Theme.radiusSm
                                                color: Theme.bgCard
                                                border.color: Theme.borderMedium
                                            }
                                            contentItem: TextInput {
                                                text: imageKeepDaysBox.textFromValue(imageKeepDaysBox.value, imageKeepDaysBox.locale)
                                                color: Theme.textPrimary
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontBody
                                                horizontalAlignment: Qt.AlignHCenter
                                                verticalAlignment: Qt.AlignVCenter
                                                readOnly: !imageKeepDaysBox.editable
                                                validator: imageKeepDaysBox.validator
                                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                            }
                                        }
                                    }

                                    Text {
                                        text: "超过此天数的检测图片及对应记录将自动删除释放磁盘空间"
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }
                            }

                            // 2. 日志保留期限
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 80
                                radius: Theme.radiusSm
                                color: Theme.bgInput
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "📑 日志保留期限:"
                                            color: Theme.textPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontBody
                                            font.weight: Theme.weightMedium
                                        }
                                        Item { Layout.fillWidth: true }
                                        SpinBox {
                                            id: logKeepDaysBox
                                            Layout.preferredWidth: 96
                                            Layout.preferredHeight: 28
                                            from: 1
                                            to: 3650
                                            value: appController ? appController.cleanupLogKeepDays() : 30
                                            onValueChanged: {
                                                if (appController) appController.setCleanupLogKeepDays(value)
                                            }
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontBody
                                            background: Rectangle {
                                                radius: Theme.radiusSm
                                                color: Theme.bgCard
                                                border.color: Theme.borderMedium
                                            }
                                            contentItem: TextInput {
                                                text: logKeepDaysBox.textFromValue(logKeepDaysBox.value, logKeepDaysBox.locale)
                                                color: Theme.textPrimary
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontBody
                                                horizontalAlignment: Qt.AlignHCenter
                                                verticalAlignment: Qt.AlignVCenter
                                                readOnly: !logKeepDaysBox.editable
                                                validator: logKeepDaysBox.validator
                                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                            }
                                        }
                                    }

                                    Text {
                                        text: "超过此天数的系统运行日志文件将自动清理"
                                        color: Theme.textSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }
                            }
                        }

                        // 底部定时执行与立即清理行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Label {
                                text: "每日定时清理时间:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                            }

                            ComboBox {
                                id: runHourBoxRight
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 32
                                model: (function() {
                                    var a = []
                                    for (var i = 0; i < 24; i++) a.push((i < 10 ? "0" : "") + i + ":00")
                                    return a
                                })()
                                currentIndex: appController ? appController.cleanupRunHour() : 1
                                onCurrentIndexChanged: {
                                    if (appController) appController.setCleanupRunHour(currentIndex)
                                }
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    radius: Theme.radiusSm
                                    color: Theme.bgInput
                                    border.color: Theme.borderSubtle
                                }
                                contentItem: Text {
                                    text: runHourBoxRight.currentText
                                    color: Theme.textPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Text {
                                text: "(每日在指定时间自动启动全盘扫描清理)"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }

                            Item { Layout.fillWidth: true }

                            ActionButton {
                                Layout.preferredWidth: 108
                                Layout.preferredHeight: 32
                                text: "立即清理"
                                variant: "danger"
                                onClicked: {
                                    if (appController)
                                        appController.triggerCleanup()
                                }
                            }
                        }
                    }
                }

                // ==================== 7. 管理员安全密码设置 ====================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: pwdCol.implicitHeight + 28
                    color: Theme.bgCard
                    radius: Theme.radiusLg
                    border.width: 1
                    border.color: Theme.borderMedium

                    property string message: ""
                    property bool messageIsError: false

                    ColumnLayout {
                        id: pwdCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle { width: 3.5; height: 16; radius: 2; color: Theme.primary }
                            Label {
                                text: "管理安全密码设置"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontH2
                                font.weight: Theme.weightSemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: "修改进入系统高级设置与参数调整的安全保护密码 (默认: 123456)"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontCaption
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Label {
                                text: "当前密码:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 80
                            }
                            TextField {
                                id: currentPasswordField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                echoMode: TextInput.Password
                                placeholderText: "请输入当前管理密码"
                                placeholderTextColor: Theme.textMuted
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: currentPasswordField.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Label {
                                text: "新设密码:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 80
                            }
                            TextField {
                                id: newPasswordField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                echoMode: TextInput.Password
                                placeholderText: "请输入新设管理密码 (≥ 6 位)"
                                placeholderTextColor: Theme.textMuted
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: newPasswordField.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Label {
                                text: "确认密码:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                Layout.preferredWidth: 80
                            }
                            TextField {
                                id: confirmPasswordField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                echoMode: TextInput.Password
                                placeholderText: "请再次输入新设管理密码"
                                placeholderTextColor: Theme.textMuted
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontBody
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSm
                                    border.color: confirmPasswordField.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10

                            ActionButton {
                                id: changePasswordButton
                                text: "确认修改"
                                variant: "primary"
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 84
                                enabled: currentPasswordField.text.length > 0
                                         && newPasswordField.text.length >= 6
                                         && confirmPasswordField.text.length > 0
                                         && newPasswordField.text === confirmPasswordField.text
                                onClicked: {
                                    if (!appController) return
                                    if (newPasswordField.text !== confirmPasswordField.text) {
                                        pwdCol.parent.message = "两次密码不一致"
                                        pwdCol.parent.messageIsError = true
                                        return
                                    }
                                    if (appController.changeSettingsPassword(currentPasswordField.text, newPasswordField.text)) {
                                        pwdCol.parent.message = "密码修改成功"
                                        pwdCol.parent.messageIsError = false
                                        currentPasswordField.text = ""
                                        newPasswordField.text = ""
                                        confirmPasswordField.text = ""
                                    } else {
                                        pwdCol.parent.message = "原密码错误或保存失败"
                                        pwdCol.parent.messageIsError = true
                                    }
                                }
                            }

                            ActionButton {
                                text: "重置初始"
                                variant: "secondary"
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 84
                                onClicked: {
                                    if (appController && appController.resetSettingsPassword()) {
                                        pwdCol.parent.message = "已恢复为默认 123456"
                                        pwdCol.parent.messageIsError = false
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: pwdCol.parent.message
                                color: pwdCol.parent.messageIsError ? Theme.ngLight : Theme.okLight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: Theme.weightMedium
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
