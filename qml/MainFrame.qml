import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

import "qrc:/qt/qml/CarrierVision/qml"

Window {
    id: mainwindow
    width: 1280
    height: 800
    visible: true
    title: qsTr("Carrier 自动点检终端系统")
    color: Theme.bgApp

    flags: Qt.FramelessWindowHint
    visibility: Window.Maximized

    // ========== 初始化 ==========
    Component.onCompleted: {
        if (typeof appController !== "undefined" && appController && appController.isDarkMode) {
            Theme.isDark = appController.isDarkMode();
        }
        navMenu.currentIndex = 0;
        statusBar.updateTextById("status", "系统已就绪");
        statusBar.updateColorById("status", Theme.ok);

        // 后台静默预热 3D 数字孪生模型缓存，确保全局任何页面调用零延迟秒开
        Qt.callLater(function () {
            DesignShowCache.getOrCreateCore();
        });
    }

    Connections {
        target: (typeof appController !== "undefined") ? appController : null
        function onDarkModeChanged(dark) {
            if (Theme.isDark !== dark) {
                Theme.isDark = dark;
            }
        }
    }

    // ========== 布局尺寸 ==========
    property int headerHeight: 60
    property int navHeight: 52
    property int statusBarHeight: 32
    property string alignment: "left"
    readonly property color panelDark: Theme.bgApp
    readonly property int settingsMenuIndex: {
        for (var i = 0; i < menuData.length; i++) {
            if (menuData[i].title === "系统设置")
                return i;
        }
        return 7;
    }
    property bool exitConfirmed: false

    // 设置访问验证（在设置页内保持有效60s；推出设置页开始倒计时，重新进入恢复到60s）
    property bool isSettingsAuthorized: false
    property int settingsAuthRemainingSeconds: 0
    property bool settingsCountdownRunning: false
    property double lastLeaveSettingsTime: 0
    readonly property int settingsAuthTimeoutMs: 60000

    function isSettingsAuthValid() {
        if (!isSettingsAuthorized)
            return false;
        if (navMenu.currentIndex === settingsMenuIndex)
            return true;
        return settingsAuthRemainingSeconds > 0;
    }

    // 成功通过密码验证时授权
    function grantSettingsAuth() {
        isSettingsAuthorized = true;
        settingsAuthRemainingSeconds = 60;
        settingsCountdownRunning = false;
        settingsAuthTimer.stop();
    }

    // 推出设置页面开始倒计时
    function onLeaveSettingsPage() {
        if (!isSettingsAuthorized)
            return;
        lastLeaveSettingsTime = Date.now();
        settingsAuthRemainingSeconds = 60;
        settingsCountdownRunning = true;
        settingsAuthTimer.restart();
    }

    // 进入设置页面后恢复到60S并停止倒计时
    function onEnterSettingsPage() {
        if (!isSettingsAuthorized)
            return;
        settingsAuthRemainingSeconds = 60;
        settingsCountdownRunning = false;
        settingsAuthTimer.stop();
    }

    // 倒计时每秒触发
    function updateSettingsAuthCountdown() {
        if (!settingsCountdownRunning || !isSettingsAuthorized) {
            return;
        }
        var elapsed = Date.now() - lastLeaveSettingsTime;
        var remMs = settingsAuthTimeoutMs - elapsed;
        if (remMs > 0) {
            settingsAuthRemainingSeconds = Math.ceil(remMs / 1000);
        } else {
            // 倒计时结束，登录密码授权失效
            settingsAuthRemainingSeconds = 0;
            isSettingsAuthorized = false;
            settingsCountdownRunning = false;
            settingsAuthTimer.stop();
            statusBar.updateStatus("管理员密码授权已过期，再次进入设置需重新验证");
        }
    }

    Timer {
        id: settingsAuthTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: mainwindow.updateSettingsAuthCountdown()
    }

    function quitSystem() {
        exitConfirmed = true;
        if (appController && appController.stopFtpServer)
            appController.stopFtpServer();
        Qt.quit();
    }

    onClosing: function (close) {
        if (exitConfirmed)
            return;
        close.accepted = false;
        if (!exitPasswordDialog.visible)
            exitPasswordDialog.open();
    }

    Connections {
        target: appController
        function onGenericSearchRequested(startDate, endDate, wheelNumber, resultType) {
            var searchIdx = -1;
            for (var i = 0; i < mainwindow.menuData.length; i++) {
                if (mainwindow.menuData[i].title === "数据查询" || (mainwindow.menuData[i].pageSource && mainwindow.menuData[i].pageSource.indexOf("SearchWorkspace.qml") !== -1)) {
                    searchIdx = i;
                    break;
                }
            }
            if (searchIdx >= 0) {
                navMenu.navigateTo(searchIdx, mainwindow.menuData[searchIdx]);
                Qt.callLater(function () {
                    if (contentLoader.item && contentLoader.item.openGenericQuery)
                        contentLoader.item.openGenericQuery(startDate, endDate, wheelNumber, resultType);
                });
            }
        }
    }

    // ========== 菜单数据 ==========
    property var menuData: [
        {
            title: "首页",
            iconName: "nav_home",
            iconText: "⌂",
            pageSource: "home/HomeWorkspace.qml"
        },
        {
            title: "热力矩阵",
            iconName: "nav_monitor",
            iconText: "▦",
            pageSource: "monitor/MonitorWorkspace.qml"
        },
        {
            title: "数据查询",
            iconName: "nav_search",
            iconText: "☵",
            pageSource: "search/SearchWorkspace.qml",
            enabled: true
        },
        {
            title: "统计分析",
            iconName: "nav_stats",
            iconText: "☲",
            pageSource: "stats/StatsWorkspace.qml",
            enabled: true
        },
        {
            title: "报警统计",
            iconName: "nav_alert",
            iconText: "▲",
            pageSource: "alert/AlertWorkspace.qml",
            enabled: true
        },
        {
            title: "日志查询",
            iconName: "nav_log",
            iconText: "🗎",
            pageSource: "log/LogWorkspace.qml",
            enabled: true
        },
        {
            title: "系统设置",
            iconName: "nav_settings",
            iconText: "⚙",
            pageSource: "settings/SettingsWorkspace.qml",
            enabled: true
        }
    ]

    // ========== 状态栏数据 ==========
    property var statusItems: [
        {
            modelId: "status",
            iconText: "●",
            text: "系统就绪",
            textColor: Theme.ok,
            width: 110
        },
        {
            modelId: "tcpstatus",
            iconText: "⚡",
            text: "等待连接",
            textColor: Theme.textSecondary,
            width: 110
        },
        {
            modelId: "tcpdata",
            iconText: "◈",
            text: "",
            textColor: Theme.textSecondary
        }
    ]

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 0

        // 1. 顶部栏
        HeadBar {
            id: head
            Layout.fillWidth: true
            Layout.preferredHeight: mainwindow.headerHeight
            systemName: "Carrier 自动点检终端系统"
            onExit: {
                exitPasswordDialog.open();
            }
            onNavigateRequested: (index, subAction) => {
                if (index >= 0 && index < mainwindow.menuData.length) {
                    if (navMenu.activationHandler && navMenu.activationHandler(index, mainwindow.menuData[index]) === false) {
                        return;
                    }
                    navMenu.navigateTo(index, mainwindow.menuData[index]);
                    if (subAction !== undefined && subAction !== null) {
                        Qt.callLater(function () {
                            var item = (index === 0) ? homePageLoader.item : contentLoader.item;
                            if (!item) return;
                            if (typeof subAction === "number") {
                                if (typeof item.switchTab === "function") {
                                    item.switchTab(subAction);
                                }
                            } else if (typeof subAction === "string") {
                                if (subAction === "twin" && typeof item.currentLeftCardView !== "undefined") {
                                    item.currentLeftCardView = 0;
                                } else if (subAction === "station" && typeof item.currentLeftCardView !== "undefined") {
                                    item.currentLeftCardView = 1;
                                } else if (subAction === "today" && typeof item.openGenericQuery === "function") {
                                    var today = new Date().toISOString().slice(0, 10);
                                    item.openGenericQuery(today + " 00:00:00", today + " 23:59:59", 0, "");
                                } else if (subAction === "ng" && typeof item.openGenericQuery === "function") {
                                    item.openGenericQuery("", "", 0, "NG");
                                } else if (typeof item.filterByLevel === "function") {
                                    item.filterByLevel(subAction);
                                }
                            }
                        });
                    }
                }
            }
        }

        // F11 快捷键切换全屏
        Shortcut {
            sequence: "F11"
            onActivated: head.toggleFullScreen()
        }

        // 2. 导航菜单 (内嵌水平导航栏)
        Rectangle {
            id: navMenu
            Layout.fillWidth: true
            Layout.preferredHeight: mainwindow.navHeight
            color: Theme.bgNav

            // 底部细微分割线
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.borderSubtle
            }

            property var menuData: mainwindow.menuData
            property Loader targetLoader: null
            property int currentIndex: 0
            property int previousIndex: 0
            property int itemWidth: 120
            property int margins: 14
            property int iconSize: 16
            property int settingsMenuIndex: mainwindow.settingsMenuIndex
            property string settingsCountdown: (mainwindow.settingsCountdownRunning && mainwindow.settingsAuthRemainingSeconds > 0) ? (mainwindow.settingsAuthRemainingSeconds + "s") : ""
            property int settingsCountdownRemaining: mainwindow.settingsAuthRemainingSeconds
            property var activationHandler: function (index, itemData) {
                if (index === mainwindow.settingsMenuIndex) {
                    if (mainwindow.isSettingsAuthValid()) {
                        return true;
                    }
                    settingsPasswordDialog.open();
                    return false;
                }
                return true;
            }

            signal menuClicked(int index, var itemData)

            function navigateTo(idx, itemData) {
                currentIndex = idx;
                if (targetLoader && itemData && itemData.pageSource)
                    targetLoader.source = itemData.pageSource;
                menuClicked(idx, itemData);
            }

            onMenuClicked: (index, itemData) => {
                statusBar.updateStatus("当前模块: " + itemData.title);

                // 从推出设置页面开始倒计时；进入设置页面后恢复到60S并停止倒计时
                if (navMenu.previousIndex === mainwindow.settingsMenuIndex && index !== mainwindow.settingsMenuIndex) {
                    mainwindow.onLeaveSettingsPage();
                } else if (index === mainwindow.settingsMenuIndex) {
                    mainwindow.onEnterSettingsPage();
                }
                navMenu.previousIndex = index;

                if (index === 0) {
                    contentLoader.source = "";
                } else if (itemData && itemData.pageSource) {
                    contentLoader.source = itemData.pageSource;
                }
            }

            ListView {
                id: navListView
                anchors {
                    fill: parent
                    leftMargin: navMenu.margins
                    rightMargin: navMenu.margins
                }
                orientation: ListView.Horizontal
                model: navMenu.menuData
                currentIndex: navMenu.currentIndex
                spacing: 4
                interactive: false

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Item {
                    id: delegateRoot
                    required property var modelData
                    required property int index

                    readonly property bool isSettingsItem: (delegateRoot.index === navMenu.settingsMenuIndex) || (delegateRoot.itemTitle === "系统设置")
                    readonly property string countdownText: isSettingsItem ? navMenu.settingsCountdown : ""
                    readonly property bool isWarning: isSettingsItem && navMenu.settingsCountdownRemaining <= 10 && navMenu.settingsCountdownRemaining > 0

                    width: navMenu.itemWidth
                    height: navListView.height > 0 ? navListView.height : 52

                    readonly property bool itemDisabled: Boolean(delegateRoot.modelData && delegateRoot.modelData.enabled === false)
                    readonly property bool itemHovered: mouseArea.containsMouse && !itemDisabled
                    readonly property bool itemSelected: delegateRoot.index === navMenu.currentIndex && !itemDisabled
                    readonly property string itemTitle: (delegateRoot.modelData && delegateRoot.modelData.title) ? String(delegateRoot.modelData.title) : ""
                    readonly property string itemIcon: (delegateRoot.modelData && delegateRoot.modelData.iconText) ? String(delegateRoot.modelData.iconText) : "●"
                    readonly property string itemIconName: (delegateRoot.modelData && delegateRoot.modelData.iconName) ? String(delegateRoot.modelData.iconName) : ""

                    Rectangle {
                        id: itemBg
                        anchors.fill: parent
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        radius: Theme.radiusMd
                        color: delegateRoot.itemSelected ? Theme.bgCardActive : (delegateRoot.itemHovered ? Theme.bgCardElevated : "transparent")

                        border.width: 1
                        border.color: delegateRoot.itemSelected ? Theme.primary : (delegateRoot.itemHovered ? Theme.borderMedium : "transparent")

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

                        // 底部选中发光微线
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: (delegateRoot.itemSelected && itemBg.width > 24) ? (itemBg.width - 24) : 0
                            height: 2
                            radius: 1
                            color: Theme.primaryLight
                            visible: delegateRoot.itemSelected

                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.animNormal
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            AppIcon {
                                id: vectorIcon
                                visible: delegateRoot.itemIconName !== ""
                                name: delegateRoot.itemIconName
                                size: navMenu.iconSize
                                color: delegateRoot.itemSelected ? Theme.primaryLight : (delegateRoot.itemHovered ? Theme.textPrimary : Theme.textSecondary)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }

                            Text {
                                id: iconText
                                visible: delegateRoot.itemIconName === ""
                                text: delegateRoot.itemIcon
                                font.pixelSize: navMenu.iconSize
                                color: delegateRoot.itemSelected ? Theme.primaryLight : (delegateRoot.itemHovered ? Theme.textPrimary : Theme.textSecondary)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }

                            Text {
                                id: titleText
                                text: delegateRoot.itemTitle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                font.weight: delegateRoot.itemSelected ? Theme.weightSemiBold : Theme.weightNormal
                                color: delegateRoot.itemSelected ? Theme.textPrimary : (delegateRoot.itemHovered ? Theme.textPrimary : Theme.textSecondary)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }
                            }
                        }

                        // 右上角浮动标签模式的倒计时徽章 (不影响按钮尺寸，不作为按钮内文字)
                        Rectangle {
                            id: countdownBadge
                            visible: delegateRoot.countdownText !== ""
                            anchors.top: itemBg.top
                            anchors.topMargin: -5
                            anchors.right: itemBg.right
                            anchors.rightMargin: -3
                            z: 10
                            height: 18
                            width: Math.max(26, badgeText.implicitWidth + 8)
                            radius: 9
                            color: delegateRoot.isWarning ? Theme.ng : Theme.primary
                            border.width: 1.5
                            border.color: Theme.isDark ? Theme.bgNav : Theme.textInverse

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.animFast
                                }
                            }

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: delegateRoot.countdownText
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightBold
                                color: Theme.textInverse
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: delegateRoot.itemDisabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !delegateRoot.itemDisabled

                            ToolTip.visible: delegateRoot.itemHovered && delegateRoot.countdownText !== ""
                            ToolTip.text: "管理员密码免密有效倒计时: " + delegateRoot.countdownText + " (重新进入设置可刷新至60秒)"
                            ToolTip.delay: 300

                            onClicked: {
                                if (navMenu.activationHandler && navMenu.activationHandler(delegateRoot.index, delegateRoot.modelData) === false)
                                    return;
                                navMenu.navigateTo(delegateRoot.index, delegateRoot.modelData);
                            }
                        }
                    }
                }
            }
        }

        // 3. 核心内容区
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: mainwindow.panelDark

            // 首页常驻 Loader：避免 3D 装配体模型 (Assembly.glb) 与着色器重复销毁/解析重建，实现 0ms 瞬间切换
            Loader {
                id: homePageLoader
                anchors.fill: parent
                anchors.margins: 10
                source: "home/HomeWorkspace.qml"
                visible: navMenu.currentIndex === 0
            }

            // 其它子模块动态 Loader
            Loader {
                id: contentLoader
                anchors.fill: parent
                anchors.margins: 10
                visible: navMenu.currentIndex !== 0

                onStatusChanged: {
                    if (status === Loader.Loading) {
                        statusBar.updateTextById("status", "模块加载中...");
                    } else if (status === Loader.Ready) {
                        statusBar.updateTextById("status", "系统就绪");
                    }
                }
            }
        }

        // 4. 底部状态栏
        StatusBar {
            id: statusBar
            Layout.fillWidth: true
            Layout.preferredHeight: mainwindow.statusBarHeight
            Layout.maximumHeight: mainwindow.statusBarHeight
            Layout.minimumHeight: mainwindow.statusBarHeight

            statusItems: mainwindow.statusItems

            onItemClicked: function(index, itemData) {
                if (itemData)
                    console.log("状态栏点击:", itemData.modelId, itemData.text);
            }
        }
    }

    // ========== 设置验证模态弹窗 ==========
    Dialog {
        id: settingsPasswordDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 420
        padding: 0
        modal: true
        closePolicy: Popup.CloseOnEscape

        property string errorMessage: ""

        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
        }

        header: Rectangle {
            implicitHeight: 68
            color: Theme.bgCardElevated
            radius: Theme.radiusLg

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Theme.primaryGlow
                    border.color: Theme.primary
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_lock"
                        size: 18
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        text: "安全设置访问验证"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        text: "请输入管理员密码以进入系统设置"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Button {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    text: "✕"
                    onClicked: settingsPasswordDialog.close()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textMuted
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 14
                        color: parent.hovered ? Theme.bgCardActive : "transparent"
                    }
                }
            }
        }

        onOpened: {
            passwordInput.text = "";
            errorMessage = "";
            passwordInput.forceActiveFocus();
            Qt.callLater(function () {
                appController.activateEnglishInputMethod();
            });
        }

        onAccepted: {
            if (appController && appController.verifySettingsPassword(passwordInput.text)) {
                mainwindow.grantSettingsAuth();
                navMenu.navigateTo(mainwindow.settingsMenuIndex, mainwindow.menuData[mainwindow.settingsMenuIndex]);
                close();
                return;
            }

            errorMessage = "密码错误，请重新输入";
            passwordInput.selectAll();
            passwordInput.forceActiveFocus();
        }

        contentItem: Item {
            implicitHeight: passwordContent.implicitHeight + 24

            ColumnLayout {
                id: passwordContent
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 16
                anchors.bottomMargin: 8
                spacing: 10

                TextField {
                    id: passwordInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhLatinOnly | Qt.ImhNoPredictiveText
                    placeholderText: "请输入密码"
                    placeholderTextColor: Theme.textMuted
                    color: Theme.textPrimary
                    font.family: Theme.fontMono
                    selectByMouse: true
                    onActiveFocusChanged: {
                        if (activeFocus)
                            appController.activateEnglishInputMethod();
                    }
                    onAccepted: settingsPasswordDialog.accept()

                    background: Rectangle {
                        radius: Theme.radiusMd
                        color: Theme.bgInput
                        border.width: 1
                        border.color: passwordInput.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsPasswordDialog.errorMessage !== ""
                    text: settingsPasswordDialog.errorMessage
                    color: Theme.ngLight
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        footer: Rectangle {
            implicitHeight: 58
            color: Theme.bgCardElevated
            radius: Theme.radiusLg

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                ActionButton {
                    text: "取消"
                    variant: "secondary"
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 34
                    onClicked: settingsPasswordDialog.close()
                }

                ActionButton {
                    text: "确认"
                    variant: "primary"
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 34
                    onClicked: settingsPasswordDialog.accept()
                }
            }
        }
    }

    // ========== 退出确认模态弹窗 ==========
    Dialog {
        id: exitPasswordDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 420
        padding: 0
        modal: true
        closePolicy: Popup.CloseOnEscape
        property string errorMessage: ""

        background: Rectangle {
            radius: Theme.radiusLg
            color: Theme.bgPopup
            border.width: 1
            border.color: Theme.borderMedium
        }

        header: Rectangle {
            implicitHeight: 68
            color: Theme.bgCardElevated
            radius: Theme.radiusLg

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Theme.ngBg
                    border.color: Theme.ng
                    border.width: 1

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_close"
                        size: 18
                        color: Theme.ng
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        text: "确认退出点检系统"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        text: "退出将终止实时采集与 FTP 服务"
                        color: Theme.ngLight
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Button {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    text: "✕"
                    onClicked: exitPasswordDialog.close()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textMuted
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 14
                        color: parent.hovered ? Theme.bgCardActive : "transparent"
                    }
                }
            }
        }

        onOpened: {
            exitPasswordInput.text = "";
            errorMessage = "";
            exitPasswordInput.forceActiveFocus();
            Qt.callLater(function () {
                appController.activateEnglishInputMethod();
            });
        }

        onAccepted: {
            if (appController && appController.verifySettingsPassword(exitPasswordInput.text)) {
                close();
                mainwindow.quitSystem();
                return;
            }
            errorMessage = "密码错误，请重新输入";
            exitPasswordInput.selectAll();
            exitPasswordInput.forceActiveFocus();
        }

        contentItem: Item {
            implicitHeight: exitPasswordContent.implicitHeight + 24

            ColumnLayout {
                id: exitPasswordContent
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 16
                anchors.bottomMargin: 8
                spacing: 10

                TextField {
                    id: exitPasswordInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhLatinOnly | Qt.ImhNoPredictiveText
                    placeholderText: "请输入设置密码以确认退出"
                    placeholderTextColor: Theme.textMuted
                    color: Theme.textPrimary
                    font.family: Theme.fontMono
                    selectByMouse: true
                    onActiveFocusChanged: {
                        if (activeFocus)
                            appController.activateEnglishInputMethod();
                    }
                    onAccepted: exitPasswordDialog.accept()

                    background: Rectangle {
                        radius: Theme.radiusMd
                        color: Theme.bgInput
                        border.width: 1
                        border.color: exitPasswordInput.activeFocus ? Theme.ng : Theme.borderMedium
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: exitPasswordDialog.errorMessage !== ""
                    text: exitPasswordDialog.errorMessage
                    color: Theme.ngLight
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        footer: Rectangle {
            implicitHeight: 58
            color: Theme.bgCardElevated
            radius: Theme.radiusLg

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                ActionButton {
                    text: "取消"
                    variant: "secondary"
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 34
                    onClicked: exitPasswordDialog.close()
                }

                ActionButton {
                    text: "确认退出"
                    variant: "danger"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 34
                    onClicked: exitPasswordDialog.accept()
                }
            }
        }
    }
}
