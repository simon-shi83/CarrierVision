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

    // ===== 服务运行真实状态监听 =====
    readonly property bool hasAppController: typeof appController !== "undefined" && appController !== null
    readonly property bool tcpRunning: hasAppController && Boolean(appController.serverRunning)
    readonly property bool ftpRunning: hasAppController && Boolean(appController.ftpRunning)
    readonly property bool allServicesRunning: tcpRunning && ftpRunning

    readonly property string masterStatusText: {
        if (tcpRunning && ftpRunning)
            return "正常运行";
        if (tcpRunning && !ftpRunning)
            return "FTP 异常";
        if (!tcpRunning && ftpRunning)
            return "TCP 异常";
        return "服务离线";
    }

    readonly property color masterStatusColor: {
        if (tcpRunning && ftpRunning)
            return Theme.ok;
        if (tcpRunning || ftpRunning)
            return Theme.warning;
        return Theme.ng;
    }

    readonly property color masterStatusBg: {
        if (tcpRunning && ftpRunning)
            return Theme.okBg;
        if (tcpRunning || ftpRunning)
            return Theme.warningBg;
        return Theme.ngBg;
    }

    readonly property color masterStatusBorder: {
        if (tcpRunning && ftpRunning)
            return Theme.okBorder;
        if (tcpRunning || ftpRunning)
            return Theme.warningBorder;
        return Theme.ngBorder;
    }

    // ===== 信号 =====
    signal exit
    signal navigateRequested(int index, var subAction)
    signal searchRequested(string startDate, string endDate, int wheelNumber, string resultType)

    // 全屏工控沉浸模式切换方法 (原生调用 QWindow C++ showFullScreen / showMaximized)
    function toggleFullScreen() {
        var win = null;
        if (root.Window && root.Window.window) {
            win = root.Window.window;
        } else if (typeof mainwindow !== "undefined" && mainwindow) {
            win = mainwindow;
        }
        if (!win)
            return;

        if (win.visibility === Window.FullScreen) {
            win.showMaximized();
        } else {
            win.showFullScreen();
        }
    }

    // 窗口平滑拖拽交互区（双击切换最大化/还原）
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        onPressed: {
            if (Window.window && Window.window.visibility !== Window.Maximized)
                Window.window.startSystemMove();
        }
        onDoubleClicked: {
            if (Window.window) {
                if (Window.window.visibility === Window.Maximized)
                    Window.window.showNormal();
                else
                    Window.window.showMaximized();
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

    // ===== 核心三段式黄金律布局 (左品牌 · 中全局检索 · 右控制集群) =====
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

                    // 1. 系统总览运行状态脉冲药丸徽章
                    Rectangle {
                        id: masterStatusBadge
                        Layout.preferredHeight: 18
                        implicitWidth: masterBeaconRow.implicitWidth + 10
                        radius: Theme.radiusPill
                        color: root.masterStatusBg
                        border.color: root.masterStatusBorder
                        border.width: 1

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

                        RowLayout {
                            id: masterBeaconRow
                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: root.masterStatusColor

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: 1.0
                                        to: 0.25
                                        duration: root.allServicesRunning ? 900 : 500
                                        easing.type: Easing.InOutQuad
                                    }
                                    NumberAnimation {
                                        from: 0.25
                                        to: 1.0
                                        duration: root.allServicesRunning ? 900 : 500
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }

                            Text {
                                text: root.masterStatusText
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontMicro
                                font.letterSpacing: Theme.letterSpacingWide
                                font.weight: Theme.weightBold
                                color: root.masterStatusColor
                            }
                        }

                        MouseArea {
                            id: masterHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        ToolTip.visible: masterHover.containsMouse
                        ToolTip.delay: 200
                        ToolTip.text: {
                            var tip = "【系统服务运行状态】\n";
                            tip += "• TCP 消息服务: " + (root.tcpRunning ? ("正常监听中 (端口 " + (root.hasAppController ? appController.listenPort : 22345) + ")") : "未启动或异常停止") + "\n";
                            tip += "• FTP 图像服务: " + (root.ftpRunning ? ("正常运行中 (端口 " + (root.hasAppController ? appController.ftpPort : 21) + ")") : "未启动或异常停止 (端口可能被占用)");
                            return tip;
                        }
                    }
                }

                Text {
                    text: "CARRIER AUTO-INSPECTION TERMINAL SYSTEM"
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

        // ==================== 2. 中间：全局检索输入条与高精时钟仪表 ====================
        RowLayout {
            spacing: 12
            Layout.alignment: Qt.AlignVCenter

            // 2.1 顶部全局检索输入条与指令速查 (VisionXR 风格)
            Item {
                id: topSearchContainer
                Layout.preferredHeight: 34
                Layout.preferredWidth: Math.min(380, Math.max(220, root.width * 0.22))

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusPill
                    color: topSearchInput.activeFocus || searchDropdownPopup.opened ? Theme.bgInput : (topSearchMouseArea.containsMouse ? Theme.bgCardActive : Theme.bgCardElevated)
                    border.color: topSearchInput.activeFocus || searchDropdownPopup.opened ? Theme.primary : (topSearchMouseArea.containsMouse ? Theme.borderHover : Theme.borderSubtle)
                    border.width: topSearchInput.activeFocus || searchDropdownPopup.opened ? 1.5 : 1

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

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        AppIcon {
                            name: "nav_search"
                            size: 14
                            color: topSearchInput.activeFocus || searchDropdownPopup.opened ? Theme.primaryLight : Theme.textMuted
                            Layout.alignment: Qt.AlignVCenter
                        }

                        TextField {
                            id: topSearchInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            placeholderText: "快速检索指令、页面、架号轮号 (Ctrl+K)..."
                            placeholderTextColor: Theme.textMuted
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontCaption
                            background: null
                            verticalAlignment: TextInput.AlignVCenter
                            padding: 0
                            selectByMouse: true

                            onPressed: {
                                if (!searchDropdownPopup.opened)
                                    searchDropdownPopup.open();
                            }
                            onTextEdited: {
                                searchDropdownPopup.selectedIndex = 0;
                                if (!searchDropdownPopup.opened)
                                    searchDropdownPopup.open();
                            }
                            Keys.onDownPressed: {
                                var filtered = searchDropdownPopup.filteredCommands();
                                if (filtered.length > 0) {
                                    searchDropdownPopup.selectedIndex = Math.min(filtered.length - 1, searchDropdownPopup.selectedIndex + 1);
                                    if (cmdListView)
                                        cmdListView.positionViewAtIndex(searchDropdownPopup.selectedIndex, ListView.Contain);
                                }
                            }
                            Keys.onUpPressed: {
                                var filtered = searchDropdownPopup.filteredCommands();
                                if (filtered.length > 0) {
                                    searchDropdownPopup.selectedIndex = Math.max(0, searchDropdownPopup.selectedIndex - 1);
                                    if (cmdListView)
                                        cmdListView.positionViewAtIndex(searchDropdownPopup.selectedIndex, ListView.Contain);
                                }
                            }
                            Keys.onEscapePressed: {
                                searchDropdownPopup.close();
                                topSearchInput.focus = false;
                            }
                            onAccepted: {
                                var filtered = searchDropdownPopup.filteredCommands();
                                if (filtered.length > 0) {
                                    var idx = Math.max(0, Math.min(filtered.length - 1, searchDropdownPopup.selectedIndex));
                                    searchDropdownPopup.executeCommand(filtered[idx]);
                                    topSearchInput.text = "";
                                    searchDropdownPopup.close();
                                    topSearchInput.focus = false;
                                }
                            }
                        }

                        // 清空按钮
                        Rectangle {
                            visible: topSearchInput.text.length > 0
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            radius: 9
                            color: clearMouse.containsMouse ? Theme.bgCardActive : "transparent"
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: Theme.textMuted
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    topSearchInput.text = "";
                                    topSearchInput.forceActiveFocus();
                                }
                            }
                        }

                        // 快捷键提示徽章 (无输入时显示)
                        Rectangle {
                            visible: topSearchInput.text.length === 0
                            Layout.preferredHeight: 18
                            Layout.preferredWidth: kbdText.implicitWidth + 8
                            radius: Theme.radiusSm
                            color: Theme.bgInput
                            border.color: Theme.borderSubtle
                            border.width: 1
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: kbdText
                                anchors.centerIn: parent
                                text: "Ctrl+K"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightBold
                            }
                        }
                    }

                    MouseArea {
                        id: topSearchMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }

                // 全局快捷键 Ctrl+K
                Shortcut {
                    sequence: "Ctrl+K"
                    onActivated: {
                        topSearchInput.forceActiveFocus();
                        topSearchInput.selectAll();
                        if (!searchDropdownPopup.opened)
                            searchDropdownPopup.open();
                    }
                }

                // 下拉指令与检索弹窗 (VisionXR 风格)
                Popup {
                    id: searchDropdownPopup
                    x: (topSearchContainer.width - width) / 2
                    y: topSearchContainer.height + 6
                    width: Math.min(520, Math.max(420, root.width * 0.36))
                    implicitHeight: Math.min(430, commandColumn.implicitHeight + 16)
                    padding: 8
                    modal: false
                    focus: false
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    property int selectedIndex: 0

                    // 命令使用频率字典映射 { cmdId: count }
                    property var usageStats: ({
                            "act_fullscreen": 6,
                            "ws_home": 5,
                            "ws_search": 4,
                            "ws_search_today": 4,
                            "ws_search_ng": 3,
                            "act_open_archive": 3,
                            "ws_home_twin": 2,
                            "ws_monitor": 2,
                            "act_theme": 2
                        })

                    function getUsageCount(cmdId) {
                        return (usageStats && usageStats[cmdId]) ? Number(usageStats[cmdId]) : 0;
                    }

                    function recordCommandUsage(cmdId) {
                        if (!cmdId)
                            return;
                        var current = getUsageCount(cmdId);
                        var updated = Object.assign({}, usageStats);
                        updated[cmdId] = current + 1;
                        usageStats = updated;
                    }

                    onOpened: {
                        selectedIndex = 0;
                    }

                    function filteredCommands() {
                        var q = topSearchInput.text.trim().toLowerCase();
                        var results = [];

                        // 1. 系统核心工作区及视窗模式导航
                        var workspaces = [
                            {
                                cmdId: "ws_home",
                                wsIndex: 0,
                                title: "切换至「首页」工作区",
                                subtitle: "机构数字孪生视窗、当前批次及实时工位图像",
                                category: "工作区",
                                icon: "nav_home",
                                defaultOrder: 1
                            },
                            {
                                cmdId: "ws_home_twin",
                                wsIndex: 0,
                                subAction: "twin",
                                title: "首页：机构数字孪生 3D 视窗",
                                subtitle: "交互式 3D 机械结构位姿、轮位着色与形变孪生",
                                category: "首页视窗",
                                icon: "icon_3d",
                                defaultOrder: 2
                            },
                            {
                                cmdId: "ws_home_station",
                                wsIndex: 0,
                                subAction: "station",
                                title: "首页：工位实时点检图像视窗",
                                subtitle: "12 工位物理相机通道检测图像与点检结果实时监控",
                                category: "首页视窗",
                                icon: "icon_camera",
                                defaultOrder: 3
                            },
                            {
                                cmdId: "ws_monitor",
                                wsIndex: 1,
                                title: "切换至「热力矩阵」工作区",
                                subtitle: "48 工位全景热力图与点检阵列实时监控",
                                category: "工作区",
                                icon: "nav_monitor",
                                defaultOrder: 4
                            },
                            {
                                cmdId: "ws_search",
                                wsIndex: 2,
                                title: "切换至「数据查询」工作区",
                                subtitle: "历史点检图像、轮号、架号多维追溯检索",
                                category: "质量追溯",
                                icon: "nav_search",
                                defaultOrder: 5
                            },
                            {
                                cmdId: "ws_search_today",
                                wsIndex: 2,
                                subAction: "today",
                                title: "数据查询：快速检索今日检测记录",
                                subtitle: "自动应用当天起止时间戳并执行综合查询",
                                category: "质量追溯",
                                icon: "nav_search",
                                defaultOrder: 6
                            },
                            {
                                cmdId: "ws_search_ng",
                                wsIndex: 2,
                                subAction: "ng",
                                title: "数据查询：筛选全部 NG 缺陷图片",
                                subtitle: "快速定位带几何超差或外观缺陷的历史检测样本",
                                category: "质量追溯",
                                icon: "nav_alert",
                                defaultOrder: 7
                            },
                            {
                                cmdId: "ws_stats",
                                wsIndex: 3,
                                title: "切换至「统计分析」工作区",
                                subtitle: "驱动轮/走行轮离散度统计与周报导出",
                                category: "工作区",
                                icon: "nav_stats",
                                defaultOrder: 8
                            },
                            {
                                cmdId: "ws_stats_wheel",
                                wsIndex: 3,
                                subAction: 0,
                                title: "统计分析：轮位质量离散度看板",
                                subtitle: "驱动轮与走行轮正态分布、标准差与工序能力",
                                category: "统计分析",
                                icon: "icon_chart_bar",
                                defaultOrder: 9
                            },
                            {
                                cmdId: "ws_stats_rack",
                                wsIndex: 3,
                                subAction: 1,
                                title: "统计分析：架损分布与形变统计",
                                subtitle: "50 组托架各轮位历史累积磨损与架损趋势",
                                category: "统计分析",
                                icon: "icon_chart_line",
                                defaultOrder: 10
                            },
                            {
                                cmdId: "ws_stats_week",
                                wsIndex: 3,
                                subAction: 2,
                                title: "统计分析：周报统计与报表导出",
                                subtitle: "周期质量检测汇总、Drivers/Deformed 数据 CSV 导出",
                                category: "统计分析",
                                icon: "icon_file_text",
                                defaultOrder: 11
                            },
                            {
                                cmdId: "ws_alert",
                                wsIndex: 4,
                                title: "切换至「报警统计」工作区",
                                subtitle: "系统缺陷事件看板、统计与告警历史",
                                category: "工作区",
                                icon: "nav_alert",
                                defaultOrder: 12
                            },
                            {
                                cmdId: "ws_alert_record",
                                wsIndex: 4,
                                subAction: 0,
                                title: "报警统计：异常告警事件明细",
                                subtitle: "实时采集各工位硬件与算法触发的报警事件流水",
                                category: "报警中心",
                                icon: "icon_file_text",
                                defaultOrder: 13
                            },
                            {
                                cmdId: "ws_alert_stats",
                                wsIndex: 4,
                                subAction: 1,
                                title: "报警统计：报警频次与趋势看板",
                                subtitle: "按缺陷类型与工位通道聚合的报警占比图谱",
                                category: "报警中心",
                                icon: "icon_chart_bar",
                                defaultOrder: 14
                            },
                            {
                                cmdId: "ws_log",
                                wsIndex: 5,
                                title: "切换至「日志查询」工作区",
                                subtitle: "全生命周期运行事件与底层通讯诊断日志",
                                category: "工作区",
                                icon: "nav_log",
                                defaultOrder: 15
                            },
                            {
                                cmdId: "ws_log_error",
                                wsIndex: 5,
                                subAction: "ERROR",
                                title: "日志查询：筛选 ERROR 级故障日志",
                                subtitle: "快速诊断网络掉线、端口占用或底层错误",
                                category: "系统运维",
                                icon: "nav_alert",
                                defaultOrder: 16
                            },
                            {
                                cmdId: "ws_log_warn",
                                wsIndex: 5,
                                subAction: "WARN",
                                title: "日志查询：筛选 WARN 级警告日志",
                                subtitle: "排查通信重连、参数边界与潜在性能告警",
                                category: "系统运维",
                                icon: "nav_log",
                                defaultOrder: 17
                            },
                            {
                                cmdId: "ws_settings",
                                wsIndex: 6,
                                title: "切换至「系统设置」工作区",
                                subtitle: "TCP通讯管理、FTP服务、清理与安全密码",
                                category: "工作区",
                                icon: "nav_settings",
                                defaultOrder: 18
                            },
                            {
                                cmdId: "ws_settings_calib",
                                wsIndex: 6,
                                subAction: 0,
                                title: "系统设置：基准标定与相机映射",
                                subtitle: "12 通道相机物理通道与标准槽位几何标定",
                                category: "工程配置",
                                icon: "icon_camera",
                                defaultOrder: 19
                            },
                            {
                                cmdId: "ws_settings_config",
                                wsIndex: 6,
                                subAction: 1,
                                title: "系统设置：系统配置与网络服务",
                                subtitle: "通信端口、FTP 根目录、超期清理与管理员密码",
                                category: "系统设置",
                                icon: "nav_settings",
                                defaultOrder: 20
                            }
                        ];

                        // 2. 硬件、通信与日常工控高频操作
                        var actions = [
                            {
                                cmdId: "act_fullscreen",
                                title: "切换全屏工控沉浸模式 (F11)",
                                subtitle: "在无边框最大化与全屏真工控视界之间切换",
                                category: "界面控制",
                                icon: "icon_win_max",
                                defaultOrder: 21
                            },
                            {
                                cmdId: "act_theme",
                                title: Theme.isDark ? "切换为「简约明亮」浅色主题" : "切换为「极夜深黑」工业主题",
                                subtitle: "一键无缝切换昼夜对比度界面视觉系统",
                                category: "界面控制",
                                icon: Theme.isDark ? "icon_sun" : "icon_moon",
                                defaultOrder: 22
                            },
                            {
                                cmdId: "act_tcp_start",
                                title: "启动 TCP 点检通信服务",
                                subtitle: "开启 22345 端口监听，接收外部 PLC 点检信号",
                                category: "通信控制",
                                icon: "icon_check_circle",
                                defaultOrder: 23
                            },
                            {
                                cmdId: "act_tcp_stop",
                                title: "停止 TCP 点检通信服务",
                                subtitle: "暂时停止 TCP 端口监听，暂停点检信号接收",
                                category: "通信控制",
                                icon: "icon_close",
                                defaultOrder: 24
                            },
                            {
                                cmdId: "act_ftp_start",
                                title: "启动 FTP 图像接收服务",
                                subtitle: "开启 FTP 上传通道，恢复工位检测图片接收",
                                category: "通信控制",
                                icon: "icon_check_circle",
                                defaultOrder: 25
                            },
                            {
                                cmdId: "act_ftp_stop",
                                title: "停止 FTP 图像接收服务",
                                subtitle: "暂时停止 FTP 服务端口与客户端连接",
                                category: "通信控制",
                                icon: "icon_close",
                                defaultOrder: 26
                            },
                            {
                                cmdId: "act_open_archive",
                                title: "打开本地图像归档存储目录",
                                subtitle: "在本地文件管理器中直接定位检测图片存储路径",
                                category: "数据存储",
                                icon: "icon_file_text",
                                defaultOrder: 27
                            },
                            {
                                cmdId: "act_open_logs",
                                title: "打开系统运行日志目录 (logs)",
                                subtitle: "在本地文件管理器中查看每日切分日志文件",
                                category: "系统运维",
                                icon: "nav_log",
                                defaultOrder: 28
                            },
                            {
                                cmdId: "act_open_ftp_root",
                                title: "打开 FTP 上传根目录",
                                subtitle: "查看外部相机或工控机直接写入的原始上传目录",
                                category: "数据存储",
                                icon: "icon_file_text",
                                defaultOrder: 29
                            },
                            {
                                cmdId: "act_cleanup",
                                title: "立即执行超期历史数据清理",
                                subtitle: "依据系统配置天数，即时扫描并删除超期图像与旧日志",
                                category: "系统维护",
                                icon: "nav_alert",
                                defaultOrder: 30
                            },
                            {
                                cmdId: "act_reset_mapping",
                                title: "恢复工位相机通道映射为默认 (1:1)",
                                subtitle: "重置 12 组工业相机通道至标准槽位 1:1 对应关系",
                                category: "工程配置",
                                icon: "icon_camera",
                                defaultOrder: 31
                            },
                            {
                                cmdId: "act_reset_pwd",
                                title: "重置安全管理密码为默认 (123456)",
                                subtitle: "恢复进入高级参数设置的出厂默认密码",
                                category: "安全管理",
                                icon: "icon_lock",
                                defaultOrder: 32
                            },
                            {
                                cmdId: "act_exit",
                                title: "安全退出 Carrier 终端系统",
                                subtitle: "弹出安全退出保护对话框，防止生产误触",
                                category: "系统安全",
                                icon: "icon_close",
                                defaultOrder: 33
                            }
                        ];

                        // 3. 智能动态数据检索 (轮号、架号、NG关键字)
                        var numMatch = q.match(/\d+/);
                        if (numMatch) {
                            var num = parseInt(numMatch[0]);
                            if (num >= 1 && num <= 8) {
                                results.push({
                                    cmdId: "query_wheel",
                                    wheelNum: num,
                                    title: "按轮号速查：第 " + num + " 号驱动轮检测图像",
                                    subtitle: "跳转至数据查询并自动检索驱动轮 " + num + " 历史巡检记录",
                                    category: "智能速查",
                                    icon: "nav_search",
                                    isQuery: true
                                });
                            } else if (num >= 11 && num <= 18) {
                                results.push({
                                    cmdId: "query_wheel",
                                    wheelNum: num,
                                    title: "按轮号速查：第 " + num + " 号走行轮检测图像",
                                    subtitle: "跳转至数据查询并自动检索走行轮 " + num + " 历史巡检记录",
                                    category: "智能速查",
                                    icon: "nav_search",
                                    isQuery: true
                                });
                            }
                            if (num >= 1 && num <= 50) {
                                results.push({
                                    cmdId: "query_rack",
                                    rackNum: num,
                                    title: "按架号速查：第 " + num + " 号托架点检批次",
                                    subtitle: "跳转至数据查询快速追溯第 " + num + " 架托架历史检测图片",
                                    category: "智能速查",
                                    icon: "nav_search",
                                    isQuery: true
                                });
                            }
                        }

                        if (q.indexOf("ng") >= 0 || q.indexOf("缺陷") >= 0 || q.indexOf("异常") >= 0) {
                            results.push({
                                cmdId: "query_ng",
                                title: "一键速查：全部 NG 异常缺陷图片",
                                subtitle: "跳转至数据查询自动执行 NG 缺陷过滤",
                                category: "智能速查",
                                icon: "nav_alert",
                                isQuery: true
                            });
                        }

                        // 匹配工作区
                        for (var w = 0; w < workspaces.length; ++w) {
                            var ws = workspaces[w];
                            if (q.length === 0 || ws.title.toLowerCase().indexOf(q) >= 0 || ws.subtitle.toLowerCase().indexOf(q) >= 0 || ws.category.toLowerCase().indexOf(q) >= 0) {
                                results.push(ws);
                            }
                        }

                        // 匹配快捷操作
                        for (var a = 0; a < actions.length; ++a) {
                            var act = actions[a];
                            if (q.length === 0 || act.title.toLowerCase().indexOf(q) >= 0 || act.subtitle.toLowerCase().indexOf(q) >= 0 || act.category.toLowerCase().indexOf(q) >= 0) {
                                results.push(act);
                            }
                        }

                        // 4. 按使用频率智能排序（用得最多的排在最前面）
                        // 优先级规则：
                        // 1) 动态数字直接精准命中的智能查询置顶；
                        // 2) 其余根据历史累计使用频次（usageCount）倒序排列；
                        // 3) 若频次相同，则保留默认工控预设序号（defaultOrder）。
                        results.sort(function (itemA, itemB) {
                            if (itemA.isQuery && !itemB.isQuery)
                                return -1;
                            if (!itemA.isQuery && itemB.isQuery)
                                return 1;

                            var countA = searchDropdownPopup.getUsageCount(itemA.cmdId);
                            var countB = searchDropdownPopup.getUsageCount(itemB.cmdId);
                            if (countB !== countA) {
                                return countB - countA;
                            }
                            var orderA = (itemA.defaultOrder !== undefined) ? itemA.defaultOrder : 999;
                            var orderB = (itemB.defaultOrder !== undefined) ? itemB.defaultOrder : 999;
                            return orderA - orderB;
                        });

                        return results;
                    }

                    function executeCommand(item) {
                        if (!item)
                            return;

                        // 立即关闭下拉菜单并清除输入框焦点与文字，杜绝延迟
                        searchDropdownPopup.close();
                        topSearchInput.text = "";
                        topSearchInput.focus = false;

                        // 记录使用频次，下次自动排在前面
                        searchDropdownPopup.recordCommandUsage(item.cmdId);

                        if (item.cmdId.indexOf("ws_") === 0) {
                            if (typeof root.navigateRequested === "function") {
                                root.navigateRequested(item.wsIndex, item.subAction);
                            }
                        } else if (item.cmdId === "act_fullscreen") {
                            root.toggleFullScreen();
                        } else if (item.cmdId === "act_theme") {
                            Theme.toggleTheme();
                        } else if (item.cmdId === "act_tcp_start") {
                            if (typeof appController !== "undefined" && appController && appController.startTcpServer) {
                                appController.startTcpServer();
                            }
                        } else if (item.cmdId === "act_tcp_stop") {
                            if (typeof appController !== "undefined" && appController && appController.stopTcpServer) {
                                appController.stopTcpServer();
                            }
                        } else if (item.cmdId === "act_ftp_start") {
                            if (typeof appController !== "undefined" && appController && appController.startFtpServer) {
                                appController.startFtpServer();
                            }
                        } else if (item.cmdId === "act_ftp_stop") {
                            if (typeof appController !== "undefined" && appController && appController.stopFtpServer) {
                                appController.stopFtpServer();
                            }
                        } else if (item.cmdId === "act_open_archive") {
                            if (typeof appController !== "undefined" && appController && appController.openArchiveDirectory) {
                                appController.openArchiveDirectory();
                            }
                        } else if (item.cmdId === "act_open_logs") {
                            if (typeof appController !== "undefined" && appController && appController.openLogDirectory) {
                                appController.openLogDirectory();
                            }
                        } else if (item.cmdId === "act_open_ftp_root") {
                            if (typeof appController !== "undefined" && appController && appController.openFtpRootDirectory) {
                                appController.openFtpRootDirectory();
                            }
                        } else if (item.cmdId === "act_cleanup") {
                            if (typeof appController !== "undefined" && appController && appController.triggerCleanup) {
                                appController.triggerCleanup();
                            }
                        } else if (item.cmdId === "act_reset_mapping") {
                            if (typeof appController !== "undefined" && appController && appController.resetSlotMapping) {
                                appController.resetSlotMapping();
                            }
                        } else if (item.cmdId === "act_reset_pwd") {
                            if (typeof appController !== "undefined" && appController && appController.resetSettingsPassword) {
                                appController.resetSettingsPassword();
                            }
                        } else if (item.cmdId === "act_exit") {
                            root.exit();
                        } else if (item.cmdId === "query_wheel") {
                            if (typeof appController !== "undefined" && appController && appController.genericSearchRequested) {
                                appController.genericSearchRequested("", "", item.wheelNum, "");
                            } else if (typeof root.navigateRequested === "function") {
                                root.navigateRequested(2);
                            }
                        } else if (item.cmdId === "query_rack") {
                            if (typeof root.navigateRequested === "function") {
                                root.navigateRequested(2);
                            }
                        } else if (item.cmdId === "query_ng") {
                            if (typeof root.navigateRequested === "function") {
                                root.navigateRequested(2, "ng");
                            }
                        }
                    }

                    background: Rectangle {
                        radius: Theme.radiusMd
                        color: Theme.bgPopup
                        border.color: Theme.borderMedium
                        border.width: 1

                        // 顶部高光微线条
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 1
                            color: Theme.borderHighlight
                            opacity: 0.35
                        }
                    }

                    contentItem: ColumnLayout {
                        id: commandColumn
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            Text {
                                text: topSearchInput.text.length > 0 ? "检索结果 (按高频与匹配度优先)" : "常用工控指令 (高频优先排列)"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontMicro
                                font.weight: Theme.weightBold
                                font.letterSpacing: Theme.letterSpacingWide
                                Layout.fillWidth: true
                            }
                            Text {
                                text: searchDropdownPopup.filteredCommands().length + " 项"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontMicro
                            }
                        }

                        ListView {
                            id: cmdListView
                            visible: count > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(320, count * 48)
                            implicitHeight: Layout.preferredHeight
                            clip: true
                            spacing: 2
                            model: searchDropdownPopup.filteredCommands()
                            currentIndex: searchDropdownPopup.selectedIndex

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: cmdDelegate
                                width: ListView.view.width
                                height: 46
                                radius: Theme.radiusSm
                                color: (searchDropdownPopup.selectedIndex === index || cmdMouse.containsMouse) ? Theme.bgCardActive : "transparent"
                                border.color: searchDropdownPopup.selectedIndex === index ? Theme.borderHighlight : "transparent"
                                border.width: searchDropdownPopup.selectedIndex === index ? 1 : 0

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animFast
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        radius: Theme.radiusSm
                                        color: (searchDropdownPopup.selectedIndex === index || cmdMouse.containsMouse) ? Theme.primaryGlow : Theme.bgCardElevated

                                        AppIcon {
                                            anchors.centerIn: parent
                                            name: modelData.icon || "nav_search"
                                            color: (searchDropdownPopup.selectedIndex === index || cmdMouse.containsMouse) ? Theme.primaryLight : Theme.textSecondary
                                            size: 14
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        RowLayout {
                                            spacing: 6
                                            Layout.fillWidth: true

                                            Text {
                                                text: modelData.title
                                                color: (searchDropdownPopup.selectedIndex === index || cmdMouse.containsMouse) ? Theme.primaryLight : Theme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontCaption
                                                font.weight: Theme.weightMedium
                                                elide: Text.ElideRight
                                            }

                                            // 高频标签（使用频次 >= 4 或前 3 项）
                                            Rectangle {
                                                visible: searchDropdownPopup.getUsageCount(modelData.cmdId) >= 4
                                                Layout.preferredHeight: 14
                                                implicitWidth: freqText.implicitWidth + 8
                                                radius: 3
                                                color: Qt.rgba(0.0, 0.85, 0.65, 0.15)
                                                border.color: Qt.rgba(0.0, 0.85, 0.65, 0.4)
                                                border.width: 1

                                                Text {
                                                    id: freqText
                                                    anchors.centerIn: parent
                                                    text: "高频"
                                                    color: Theme.okLight
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.weight: Theme.weightBold
                                                }
                                            }
                                        }

                                        Text {
                                            text: modelData.subtitle
                                            color: Theme.textSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontMicro
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredHeight: 18
                                        implicitWidth: catText.implicitWidth + 10
                                        radius: Theme.radiusSm
                                        color: Theme.bgInput
                                        border.color: Theme.borderSubtle
                                        border.width: 1

                                        Text {
                                            id: catText
                                            anchors.centerIn: parent
                                            text: modelData.category
                                            color: Theme.textMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontMicro
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cmdMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: {
                                        searchDropdownPopup.selectedIndex = index;
                                    }
                                    onClicked: {
                                        searchDropdownPopup.executeCommand(modelData);
                                        topSearchInput.text = "";
                                        searchDropdownPopup.close();
                                        topSearchInput.focus = false;
                                    }
                                }
                            }
                        }

                        // 空结果提示
                        Item {
                            visible: cmdListView.count === 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            implicitHeight: 76

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                AppIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    name: "nav_search"
                                    color: Theme.textMuted
                                    size: 18
                                    opacity: 0.6
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "未找到匹配的指令、工作区或点检数据"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontCaption
                                }
                            }
                        }
                    }
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
                                Window.window.showMinimized();
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
                                    Window.window.showNormal();
                                else
                                    Window.window.showMaximized();
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
