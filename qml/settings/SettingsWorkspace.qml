import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

// 系统设置：单页滚动的设置卡片。卡片内默认是两列网格（左列参数名称与说明，右列设定控件），
// 不适合两列的内容用 Layout.columnSpan: 2 占满整行
Item {
    id: root
    anchors.fill: parent

    property string homepageFeedback: ""
    property string securityMessage: ""
    property bool maintenanceSet: appController && appController.hasMaintenancePassword ? appController.hasMaintenancePassword() : false

    // ========== 卡片与行的基础组件 ==========

    // 设置卡片：标题、简介与右上角附加内容；子项通常依次放 ParamHeader、ParamValue，行间放 RowDivider
    component Section: Rectangle {
        id: section
        property string title: ""
        property string description: ""
        property alias headerExtras: extrasRow.data
        default property alias content: grid.data

        Layout.fillWidth: true
        implicitHeight: sectionCol.implicitHeight + Theme.space6 * 2
        color: Theme.surface
        radius: Theme.radiusLarge

        ColumnLayout {
            id: sectionCol
            anchors.fill: parent
            anchors.margins: Theme.space6
            spacing: Theme.space5

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space3

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        Layout.fillWidth: true
                        text: section.title
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontTitle
                        font.weight: Theme.fontMedium
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: section.description
                        wrapMode: Text.WordWrap
                        color: Theme.muted
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                    }
                }
                RowLayout {
                    id: extrasRow
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: Theme.space2
                }
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space6
                rowSpacing: Theme.space4
            }
        }
    }

    // 左列：参数名称与说明。固定宽度并顶端对齐，使各卡片的设定控件左边缘对齐
    component ParamHeader: ColumnLayout {
        id: header
        property string title: ""
        property string description: ""

        Layout.preferredWidth: 232
        Layout.minimumWidth: 232
        Layout.maximumWidth: 232
        // 与控件首行对齐
        Layout.topMargin: Theme.space1
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        spacing: Theme.space1

        Label {
            Layout.fillWidth: true
            text: header.title
            wrapMode: Text.WordWrap
            color: Theme.text
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontBody
            font.weight: Theme.fontMedium
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: header.description
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontCaption
        }
    }

    // 右列：紧跟左列、顶端对齐
    component ParamValue: RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        spacing: Theme.space2
    }

    component RowDivider: Rectangle {
        Layout.columnSpan: 2
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.borderMuted
        opacity: 0.55
    }

    component StatusBadge: Rectangle {
        id: badge
        property bool running: false
        property string text: ""

        implicitHeight: 28
        implicitWidth: badgeRow.implicitWidth + Theme.space3 * 2
        radius: Theme.radiusPill
        color: running ? Theme.okSoft : Theme.surfaceAlt

        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: Theme.space1
            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                radius: Theme.radiusPill
                color: badge.running ? Theme.ok : Theme.muted
            }
            Text {
                text: badge.text
                color: Theme.text
                font.family: Theme.fontSans
                font.features: Theme.fontFeaturesTabular
                font.pixelSize: Theme.fontCaption
                font.weight: Theme.fontMedium
            }
        }
    }

    component Field: TextField {
        id: field
        Layout.preferredHeight: 36
        leftPadding: Theme.space3
        rightPadding: Theme.space3
        selectByMouse: true
        Accessible.name: placeholderText.length > 0 ? placeholderText : "参数值"
        color: Theme.text
        placeholderTextColor: Theme.muted
        font.family: Theme.fontSans
        font.features: Theme.fontFeaturesTabular
        font.pixelSize: Theme.fontBody
        background: Rectangle {
            color: Theme.fieldFill
            radius: Theme.radiusSmall
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Theme.selectedBorder : (field.hovered ? Theme.borderStrong : Theme.border)
        }
    }

    component Combo: ComboBox {
        id: combo
        Layout.preferredHeight: 36
        palette.buttonText: Theme.text
        palette.windowText: Theme.text
        palette.text: Theme.text
        palette.base: Theme.fieldFill
        palette.button: Theme.surfaceAlt
        palette.window: Theme.surfaceFloating
        palette.highlight: Theme.accent
        palette.highlightedText: Theme.textOnAccent
        font.family: Theme.fontSans
        font.features: Theme.fontFeaturesTabular
        font.pixelSize: Theme.fontBody

        background: Rectangle {
            color: combo.hovered ? Theme.hover : Theme.fieldFill
            radius: Theme.radiusSmall
            border.width: combo.activeFocus ? 2 : 1
            border.color: (combo.activeFocus || combo.popup.visible) ? Theme.selectedBorder
                          : (combo.hovered ? Theme.borderStrong : Theme.border)
        }

        contentItem: Text {
            text: combo.displayText
            color: Theme.text
            font: combo.font
            leftPadding: Theme.space3
            rightPadding: combo.indicator ? combo.indicator.width : 0
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component DaysSpinBox: SpinBox {
        id: spin
        Layout.preferredWidth: 120
        Layout.preferredHeight: 36
        from: 1
        to: 3650
        palette.buttonText: Theme.text
        palette.windowText: Theme.text
        palette.text: Theme.text
        palette.base: Theme.fieldFill
        palette.button: Theme.surfaceAlt
        palette.window: Theme.surfaceFloating
        palette.highlight: Theme.accent
        palette.highlightedText: Theme.textOnAccent
        font.family: Theme.fontSans
        font.features: Theme.fontFeaturesTabular
        font.pixelSize: Theme.fontBody
        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.fieldFill
            border.width: 1
            border.color: spin.activeFocus ? Theme.selectedBorder : Theme.border
        }
        contentItem: TextInput {
            text: spin.textFromValue(spin.value, spin.locale)
            color: Theme.text
            font: spin.font
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            readOnly: !spin.editable
            validator: spin.validator
            inputMethodHints: Qt.ImhFormattedNumbersOnly
        }
    }

    component UnitLabel: Label {
        color: Theme.textSoft
        font.family: Theme.fontSans
        font.pixelSize: Theme.fontBody
    }

    component HintLabel: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.textSoft
        font.family: Theme.fontSans
        font.pixelSize: Theme.fontCaption
    }

    // 只读路径展示框
    component PathDisplay: Rectangle {
        property alias text: pathText.text
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        color: Theme.surfaceAlt
        radius: Theme.radiusSmall
        border.width: 1
        border.color: Theme.borderMuted

        Text {
            id: pathText
            anchors.fill: parent
            anchors.leftMargin: Theme.space3
            anchors.rightMargin: Theme.space3
            verticalAlignment: Text.AlignVCenter
            color: Theme.textSoft
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideMiddle
        }
    }

    // ========== 设置卡片 ==========

    ScrollView {
        id: settingsScroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Item {
            width: settingsScroll.availableWidth
            implicitHeight: settingsCards.implicitHeight + Theme.space5 * 2

            ColumnLayout {
                id: settingsCards
                width: Math.min(1120, parent.width - Theme.space5 * 2)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Theme.space5
                spacing: Theme.space5

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space2
                    spacing: Theme.space2

                    Label {
                        text: "系统设置"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontDisplay
                        font.weight: Theme.fontBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "管理界面显示、客户端通信与数据维护。"
                        wrapMode: Text.WordWrap
                        color: Theme.textSoft
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontBody
                    }
                }

                // ---------- 主页与主题 ----------
                Section {
                    title: "主页与主题"
                    description: "让现场信息更清晰，适应不同光照环境。"

                    ParamHeader {
                        title: "主页说明"
                        description: "设置首页展示的说明文字，修改后点击保存。"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.space2
                        TextArea {
                            id: descriptionInput
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            text: appController ? appController.homepageDescription : ""
                            placeholderText: "请输入系统主页展示的说明信息"
                            placeholderTextColor: Theme.muted
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontBody
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.fieldFill
                                border.width: 1
                                border.color: descriptionInput.activeFocus ? Theme.selectedBorder : Theme.border
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2
                            HintLabel { text: root.homepageFeedback }
                            ActionButton {
                                Layout.preferredHeight: 36
                                text: "保存说明"
                                variant: "primary"
                                onClicked: {
                                    if (appController && appController.saveHomepageDescription(descriptionInput.text)) {
                                        descriptionInput.text = appController.homepageDescription;
                                        root.homepageFeedback = "主页说明已保存";
                                    } else {
                                        root.homepageFeedback = "主页说明保存失败，请重试";
                                    }
                                }
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "界面主题"
                        description: "根据现场光照选择亮色或暗色主题，切换后立即保存。"
                    }
                    ParamValue {
                        Rectangle {
                            implicitWidth: themeRow.implicitWidth + Theme.space1 * 2
                            implicitHeight: 44
                            radius: Theme.radiusMedium
                            color: Theme.surfaceAlt

                            RowLayout {
                                id: themeRow
                                anchors.fill: parent
                                anchors.margins: Theme.space1
                                spacing: Theme.space1

                                Repeater {
                                    model: [
                                        { dark: false, label: "亮色", icon: "icon_sun" },
                                        { dark: true, label: "暗色", icon: "icon_moon" }
                                    ]
                                    delegate: Button {
                                        id: themeOption
                                        required property var modelData
                                        readonly property bool selected: modelData.dark === Theme.isDark
                                        Layout.fillHeight: true
                                        implicitWidth: 104
                                        text: modelData.label
                                        checked: selected
                                        Accessible.name: modelData.label + "主题"
                                        onClicked: Theme.setDark(modelData.dark)

                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: themeOption.down ? Theme.pressed
                                                   : themeOption.selected ? Theme.surface
                                                   : themeOption.hovered ? Theme.hover : Theme.surfaceAlt
                                            border.width: themeOption.activeFocus ? 2 : (themeOption.selected ? 1 : 0)
                                            border.color: themeOption.activeFocus ? Theme.selectedBorder : Theme.borderMuted
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                        }
                                        contentItem: RowLayout {
                                            spacing: Theme.space2
                                            Item { Layout.fillWidth: true }
                                            AppIcon {
                                                name: themeOption.modelData.icon
                                                size: 16
                                                color: themeOption.selected ? Theme.accent : Theme.textSoft
                                            }
                                            Label {
                                                text: themeOption.text
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: Theme.fontBody
                                                font.weight: themeOption.selected ? Theme.fontMedium : Theme.fontRegular
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------- 显示槽位映射 ----------
                Section {
                    title: "显示槽位映射"
                    description: "选择后立即保存，仅影响首页显示，不改变客户端配置与轮位编号。"

                    headerExtras: ActionButton {
                        Layout.preferredHeight: 36
                        text: "恢复默认"
                        variant: "secondary"
                        onClicked: {
                            if (appController)
                                appController.resetSlotMapping();
                        }
                    }

                    // 相机映射按可用宽度排列；这里只调整显示位置。
                    GridLayout {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        columns: width >= 960 ? 6 : (width >= 640 ? 4 : 3)
                        rowSpacing: Theme.space3
                        columnSpacing: Theme.space3

                        Repeater {
                            model: 12

                            delegate: Rectangle {
                                id: camItem
                                required property int index
                                readonly property int camNumber: index + 1
                                readonly property int currentSlot: {
                                    if (appController && appController.slotMapping && appController.slotMapping.length > index) {
                                        var val = Number(appController.slotMapping[index]);
                                        return (val >= 1 && val <= 12) ? val : camNumber;
                                    }
                                    return camNumber;
                                }

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: camCol.implicitHeight + Theme.space3 * 2
                                radius: Theme.radiusSmall
                                color: Theme.surfaceAlt

                                ColumnLayout {
                                    id: camCol
                                    anchors.fill: parent
                                    anchors.margins: Theme.space3
                                    spacing: Theme.space2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.space1
                                        Text {
                                            Layout.fillWidth: true
                                            text: "相机 " + (camItem.camNumber < 10 ? "0" : "") + camItem.camNumber
                                            color: Theme.textSoft
                                            font.family: Theme.fontSans
                                            font.features: Theme.fontFeaturesTabular
                                            font.pixelSize: Theme.fontCaption
                                            font.weight: Theme.fontMedium
                                        }
                                    }

                                    Combo {
                                        Layout.fillWidth: true
                                        model: ["槽位 01", "槽位 02", "槽位 03", "槽位 04", "槽位 05", "槽位 06", "槽位 07", "槽位 08", "槽位 09", "槽位 10", "槽位 11", "槽位 12"]
                                        currentIndex: Math.max(0, Math.min(11, camItem.currentSlot - 1))
                                        onActivated: {
                                            if (appController)
                                                appController.setSlotMapping(camItem.camNumber, currentIndex + 1);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- TCP 数据接收 ----------
                Section {
                    title: "TCP 数据接收"
                    description: "接收客户端上报的检测结果。"

                    headerExtras: [
                        StatusBadge {
                            running: appController ? appController.tcpRunning : false
                            text: running ? ("监听中 · " + appController.tcpClientCount + " 个客户端") : "服务已停止"
                        },
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: (appController && appController.tcpRunning) ? "停止服务" : "启动服务"
                            variant: "secondary"
                            onClicked: {
                                if (!appController)
                                    return;
                                if (appController.tcpRunning)
                                    appController.stopTcpServer();
                                else
                                    appController.startTcpServer();
                            }
                        }
                    ]

                    ParamHeader {
                        title: "监听端口"
                        description: "端口范围 1～65535。修改运行中的端口会重启服务并断开现有连接。"
                    }
                    ParamValue {
                        Field {
                            id: tcpPortInput
                            Accessible.name: "TCP 监听端口"
                            Layout.preferredWidth: 96
                            validator: IntValidator { bottom: 1; top: 65535 }
                            inputMethodHints: Qt.ImhDigitsOnly
                            text: appController ? String(appController.tcpPort) : "9000"
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "保存端口"
                            variant: "secondary"
                            enabled: tcpPortInput.acceptableInput && appController && Number(tcpPortInput.text) !== appController.tcpPort
                            onClicked: {
                                if (appController) {
                                    appController.setTcpPort(Number(tcpPortInput.text));
                                    tcpPortInput.text = String(appController.tcpPort);
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------- FTP 图像上传 ----------
                Section {
                    title: "FTP 图像上传"
                    description: "接收检测图像，并管理上传目录与访问账户。"

                    headerExtras: [
                        StatusBadge {
                            running: appController ? appController.ftpRunning : false
                            text: running ? "服务运行中" : "服务已停止"
                        },
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: (appController && appController.ftpRunning) ? "停止服务" : "启动服务"
                            variant: "secondary"
                            onClicked: {
                                if (!appController)
                                    return;
                                if (appController.ftpRunning)
                                    appController.stopFtpServer();
                                else
                                    appController.startFtpServer();
                            }
                        }
                    ]

                    ParamHeader {
                        title: "图像存储目录"
                        description: "FTP 上传目录即图像存储目录。相对路径按程序所在目录解析，例如 images。"
                    }
                    ParamValue {
                        Field {
                            id: ftpRootInput
                            Accessible.name: "图像存储目录"
                            Layout.fillWidth: true
                            text: appController ? appController.archiveDirectory : ""
                            placeholderText: "如 images"
                            font.family: Theme.fontMono
                            font.features: ({})
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "保存目录"
                            variant: "secondary"
                            enabled: ftpRootInput.text.trim().length > 0
                            onClicked: {
                                if (appController)
                                    appController.setFtpRoot(ftpRootInput.text);
                            }
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "打开目录"
                            variant: "secondary"
                            onClicked: {
                                if (appController)
                                    appController.openFtpRootDirectory();
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "访问账户"
                        description: "客户端上传图片时使用的用户名与密码。相同用户名再次保存会更新密码。"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.space2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            Field {
                                id: newUser
                                Layout.fillWidth: true
                                maximumLength: 64
                                placeholderText: "用户名"
                            }
                            Field {
                                id: newPass
                                Layout.fillWidth: true
                                maximumLength: 256
                                placeholderText: "密码"
                                echoMode: TextInput.Password
                            }
                            ActionButton {
                                Layout.preferredHeight: 36
                                text: "添加账户"
                                variant: "primary"
                                enabled: newUser.text.trim().length > 0 && newPass.text.length > 0
                                onClicked: {
                                    if (appController && newUser.text.length > 0) {
                                        appController.addFtpAccount(newUser.text, newPass.text);
                                        newUser.text = "";
                                        newPass.text = "";
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: accountsList.count === 0 ? 64
                                                    : Math.min(200, accountsList.count * 44 + Theme.space1 * 2)
                            color: Theme.surfaceAlt
                            radius: Theme.radiusSmall
                            clip: true

                            ListView {
                                id: accountsList
                                anchors.fill: parent
                                anchors.margins: Theme.space1
                                model: appController ? appController.ftpAccounts : []
                                spacing: 2

                                delegate: Rectangle {
                                    required property var modelData
                                    width: accountsList.width
                                    height: 42
                                    radius: Theme.radiusMicro
                                    color: itemMouse.containsMouse ? Theme.hover : "transparent"

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.space3
                                        anchors.rightMargin: Theme.space1
                                        spacing: Theme.space2

                                        AppIcon {
                                            name: "icon_user"
                                            size: 14
                                            color: Theme.textSoft
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData && modelData.user) ? modelData.user : ""
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.fontBody
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: (modelData && modelData.hasPassword) ? "已设密码" : "无密码"
                                            color: Theme.muted
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.fontCaption
                                        }
                                        ActionButton {
                                            Layout.preferredHeight: 28
                                            text: "删除"
                                            variant: "secondary"
                                            btnRadius: Theme.radiusMicro
                                            onClicked: {
                                                if (appController && modelData && modelData.user)
                                                    appController.removeFtpAccount(modelData.user);
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: accountsList.count === 0
                                text: "暂无访问账户，请在上方添加"
                                color: Theme.muted
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.fontCaption
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "监听端口"
                        description: "端口范围 1～65535。修改运行中的端口会重启服务，客户端需重新连接。"
                    }
                    ParamValue {
                        Field {
                            id: ftpPortInput
                            Accessible.name: "FTP 监听端口"
                            Layout.preferredWidth: 96
                            validator: IntValidator { bottom: 1; top: 65535 }
                            inputMethodHints: Qt.ImhDigitsOnly
                            text: appController ? String(appController.ftpPort) : "21"
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "保存端口"
                            variant: "secondary"
                            enabled: ftpPortInput.acceptableInput && appController && Number(ftpPortInput.text) !== appController.ftpPort
                            onClicked: {
                                if (appController) {
                                    appController.setFtpPort(Number(ftpPortInput.text));
                                    ftpPortInput.text = String(appController.ftpPort);
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------- 存储与清理 ----------
                Section {
                    title: "存储与清理"
                    description: "查看数据存放位置，设置历史数据保留策略。"

                    headerExtras: ActionButton {
                        Layout.preferredHeight: 36
                        text: "立即清理"
                        variant: "secondary"
                        onClicked: {
                            if (appController)
                                appController.triggerCleanup();
                        }
                    }

                    ParamHeader {
                        title: "图像目录"
                        description: "与 FTP 上传目录一致，可在上方 FTP 图像上传中修改。"
                    }
                    ParamValue {
                        PathDisplay {
                            text: appController ? appController.archiveDirectory : ""
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "打开目录"
                            variant: "secondary"
                            onClicked: {
                                if (appController)
                                    appController.openArchiveDirectory();
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "运行日志"
                        description: "保存在程序目录下的 logs/，每天按日期归档。"
                    }
                    ParamValue {
                        PathDisplay {
                            text: "logs/"
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "打开目录"
                            variant: "secondary"
                            onClicked: {
                                if (appController)
                                    appController.openLogDirectory();
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "保留期限"
                        description: "超过期限的检测图片、对应记录和运行日志自动清理。范围 1～3650 天，修改后立即保存。"
                    }
                    ParamValue {
                        UnitLabel { text: "图片与记录" }
                        DaysSpinBox {
                            value: appController ? appController.cleanupKeepDays() : 90
                            onValueModified: {
                                if (appController)
                                    appController.setCleanupKeepDays(value);
                            }
                        }
                        UnitLabel { text: "天" }
                        Item { implicitWidth: Theme.space5 }
                        UnitLabel { text: "日志" }
                        DaysSpinBox {
                            value: appController ? appController.cleanupLogKeepDays() : 30
                            onValueModified: {
                                if (appController)
                                    appController.setCleanupLogKeepDays(value);
                            }
                        }
                        UnitLabel { text: "天" }
                        Item { Layout.fillWidth: true }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "每日清理时间"
                        description: "每天在所选时间按保留期限执行清理，选择后立即保存。"
                    }
                    ParamValue {
                        Combo {
                            Layout.preferredWidth: 120
                            model: (function () {
                                    var a = [];
                                    for (var i = 0; i < 24; i++)
                                        a.push((i < 10 ? "0" : "") + i + ":00");
                                    return a;
                                })()
                            currentIndex: appController ? appController.cleanupRunHour() : 1
                            onActivated: {
                                if (appController)
                                    appController.setCleanupRunHour(currentIndex);
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ---------- 访问安全 ----------
                Section {
                    title: "访问安全"
                    description: "管理设置密码与维护口令。"

                    ParamHeader {
                        title: "修改设置密码"
                        description: "先填写当前密码，新密码至少 6 位并输入两次。重置将恢复为默认密码 123456。"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.space2

                        Field {
                            id: currentPasswordField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "当前设置密码"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2
                            Field {
                                id: newPasswordField
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "新密码，至少 6 位"
                            }
                            Field {
                                id: confirmPasswordField
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "再次输入新密码"
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2
                            HintLabel {
                                text: newPasswordField.text.length > 0 && confirmPasswordField.text.length > 0
                                      && newPasswordField.text !== confirmPasswordField.text ? "两次输入的新密码不一致" : ""
                            }
                            ActionButton {
                                Layout.preferredHeight: 36
                                text: "重置为默认"
                                variant: "secondary"
                                onClicked: {
                                    if (appController && appController.resetSettingsPassword())
                                        root.securityMessage = "已恢复为默认密码 123456";
                                }
                            }
                            ActionButton {
                                Layout.preferredHeight: 36
                                text: "确认修改"
                                variant: "primary"
                                enabled: currentPasswordField.text.length > 0 && newPasswordField.text.length >= 6 && newPasswordField.text === confirmPasswordField.text
                                onClicked: {
                                    if (!appController)
                                        return;
                                    if (appController.changeSettingsPassword(currentPasswordField.text, newPasswordField.text)) {
                                        root.securityMessage = "密码修改成功";
                                        currentPasswordField.text = "";
                                        newPasswordField.text = "";
                                        confirmPasswordField.text = "";
                                    } else {
                                        root.securityMessage = "原密码错误或保存失败";
                                    }
                                }
                            }
                        }
                    }

                    RowDivider {}

                    ParamHeader {
                        title: "维护口令"
                        description: "至少 6 位且不能与设置密码相同，保存时需在上方填写当前设置密码。"
                    }
                    ParamValue {
                        Field {
                            id: maintenancePasswordField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: root.maintenanceSet ? "已设置，输入新维护口令" : "未设置，输入维护口令"
                        }
                        ActionButton {
                            Layout.preferredHeight: 36
                            text: "保存口令"
                            variant: "secondary"
                            enabled: currentPasswordField.text.length > 0 && maintenancePasswordField.text.length >= 6
                            onClicked: {
                                if (!appController)
                                    return;
                                if (appController.setMaintenancePassword(currentPasswordField.text, maintenancePasswordField.text)) {
                                    root.securityMessage = "维护口令已保存";
                                    root.maintenanceSet = true;
                                    maintenancePasswordField.text = "";
                                    currentPasswordField.text = "";
                                } else {
                                    root.securityMessage = "当前密码错误，或口令不足 6 位、与设置密码相同";
                                }
                            }
                        }
                    }

                    // 操作结果提示
                    Label {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.securityMessage
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        color: Theme.textSoft
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }
        }
    }
}
