import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."
import "common"

Rectangle {
    id: statusBar
    width: parent ? parent.width : 800
    height: 32
    color: Theme.bgStatusBar
    border.width: 0

    // ==================== 顶部发光微边框与层次 ====================
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.borderSubtle
    }

    // ==================== 对外属性 (保持 100% 架构向下兼容) ====================
    property var statusItems: []

    // 默认样式
    property color backgroundColor: Theme.bgStatusBar
    property color borderColor: Theme.borderSubtle
    property color textColor: Theme.textSecondary
    property int defaultItemWidth: 0

    // 动态运行期覆盖状态消息
    property string overrideStatusMessage: ""
    property bool tcpPacketPulse: false

    // 信号
    signal itemClicked(int index, var itemData)
    signal itemDoubleClicked(int index, var itemData)

    // ==================== 智能解析状态项 ====================
    readonly property var statusItemObj: findItem("status")
    readonly property var tcpStatusItemObj: findItem("tcpstatus")
    readonly property var tcpDataItemObj: findItem("tcpdata")

    readonly property string systemStatusText: {
        // 1. 如果子页面 Loader 正在加载，优先反映加载状态
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).indexOf("加载") >= 0) {
            return String(statusItemObj.text);
        }
        // 2. 真实服务健康度感知：杜绝服务异常时盲目显示“系统就绪”
        if (!statusBar.tcpRunning && !statusBar.ftpRunning) {
            return "服务停止";
        }
        if (statusBar.tcpRunning && !statusBar.ftpRunning) {
            return "FTP 异常";
        }
        if (!statusBar.tcpRunning && statusBar.ftpRunning) {
            return "TCP 异常";
        }
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).length > 0) {
            return String(statusItemObj.text);
        }
        return "系统就绪";
    }

    readonly property color systemStatusColor: {
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).indexOf("加载") >= 0) {
            return Theme.warning;
        }
        if (!statusBar.tcpRunning && !statusBar.ftpRunning) {
            return Theme.ng;
        }
        if (!statusBar.tcpRunning || !statusBar.ftpRunning) {
            return Theme.warning;
        }
        if (statusItemObj && statusItemObj.textColor !== undefined) {
            return statusItemObj.textColor;
        }
        return Theme.ok;
    }

    // ==================== 运行期告警与日志错误优先感知 ====================
    readonly property var activeWarnOrErrorLog: {
        if (typeof appController !== "undefined" && appController && appController.latestWarnOrError) {
            var logMap = appController.latestWarnOrError;
            if (logMap && logMap.message && String(logMap.message).length > 0) {
                return logMap;
            }
        }
        return null;
    }

    // 致命服务是否异常：TCP 或 FTP 异常均属于致命故障，因为软件核心检测与接收功能已无法进行
    readonly property bool hasFatalServiceFault: !statusBar.tcpRunning || !statusBar.ftpRunning

    // 动态提示流当前严重等级: "FATAL" | "CRITICAL" | "ERROR" | "WARN" | "INFO"
    readonly property string operationalMessageLevel: {
        if (hasFatalServiceFault) {
            return "FATAL";
        }
        if (activeWarnOrErrorLog) {
            var lvl = String(activeWarnOrErrorLog.level).toUpperCase();
            if (lvl === "CRITICAL" || lvl === "FATAL") return "CRITICAL";
            if (lvl === "ERROR") return "ERROR";
            if (lvl === "WARN" || lvl === "WARNING") return "WARN";
        }
        return "INFO";
    }

    // 动态业务事件与提示文本（严格调度优先级：致命服务异常 > 日志错误 > 日志警告 > 业务/操作提示）
    readonly property string operationalMessageText: {
        // 1. 最高优先级：服务异常（致命故障：TCP 或 FTP 停止）
        if (!statusBar.tcpRunning && !statusBar.ftpRunning) {
            return "【致命故障】TCP点检通信服务与FTP图像服务均未启动！系统已无法接收点检与图像数据";
        }
        if (!statusBar.ftpRunning) {
            return "【致命故障】FTP图像接收服务未运行或端口冲突！无法接收检测机台上传的轮对图像";
        }
        if (!statusBar.tcpRunning) {
            return "【致命故障】TCP点检通信服务未启动！无法与PLC/机台进行点检闭环交互";
        }

        // 2. 第二/三优先级：日志中的 CRITICAL / ERROR / WARN 级日志
        if (activeWarnOrErrorLog) {
            var lvl = String(activeWarnOrErrorLog.level).toUpperCase();
            var timePrefix = activeWarnOrErrorLog.time ? ("[" + activeWarnOrErrorLog.time + "] ") : "";
            var tag = "";
            if (lvl === "CRITICAL" || lvl === "FATAL") tag = "【致命错误】";
            else if (lvl === "ERROR") tag = "【系统错误】";
            else if (lvl === "WARN" || lvl === "WARNING") tag = "【系统警告】";
            return tag + timePrefix + String(activeWarnOrErrorLog.message).replace(/[\r\n]+/g, " ");
        }

        // 3. 第四优先级：常规运行期提示与操作流
        if (overrideStatusMessage.length > 0) {
            return overrideStatusMessage;
        }
        if (tcpDataItemObj && tcpDataItemObj.text !== undefined && String(tcpDataItemObj.text).length > 0) {
            return String(tcpDataItemObj.text);
        }
        if (typeof appController !== "undefined" && appController && appController.statusMessage && appController.statusMessage.length > 0) {
            return appController.statusMessage;
        }
        return "就绪 · 工业级高精检测流水线待命";
    }

    readonly property color operationalMessageColor: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL" || operationalMessageLevel === "ERROR") {
            return Theme.ngLight;
        }
        if (operationalMessageLevel === "WARN") {
            return Theme.warningLight;
        }
        return Theme.textSecondary;
    }

    readonly property color operationalIconColor: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL" || operationalMessageLevel === "ERROR") {
            return Theme.ng;
        }
        if (operationalMessageLevel === "WARN") {
            return Theme.warning;
        }
        return Theme.textMuted;
    }

    readonly property string operationalIconText: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL") {
            return "⛔";
        }
        if (operationalMessageLevel === "ERROR") {
            return "✖";
        }
        if (operationalMessageLevel === "WARN") {
            return "⚠";
        }
        return "◈";
    }

    // 硬件与服务遥测数据
    readonly property bool tcpRunning: {
        if (typeof appController !== "undefined" && appController) {
            return appController.serverRunning;
        }
        return true;
    }

    readonly property int tcpPort: {
        if (typeof appController !== "undefined" && appController && appController.listenPort > 0) {
            return appController.listenPort;
        }
        return 22345;
    }

    readonly property string lastTcpMsg: {
        if (typeof appController !== "undefined" && appController && appController.lastTcpMessage) {
            return appController.lastTcpMessage;
        }
        return "";
    }

    readonly property bool ftpRunning: {
        if (typeof appController !== "undefined" && appController) {
            return appController.ftpRunning;
        }
        return true;
    }

    readonly property int ftpPort: {
        if (typeof appController !== "undefined" && appController && appController.ftpPort > 0) {
            return appController.ftpPort;
        }
        return 21;
    }

    readonly property int ftpClientCount: {
        if (typeof appController !== "undefined" && appController) {
            return appController.ftpClientCount;
        }
        return 0;
    }

    readonly property int currentRound: {
        if (typeof appController !== "undefined" && appController) {
            return appController.currentRoundNumber;
        }
        return 0;
    }

    readonly property int currentCopied: {
        if (typeof appController !== "undefined" && appController) {
            return appController.currentCopiedCount;
        }
        return 0;
    }

    readonly property int currentExpected: {
        if (typeof appController !== "undefined" && appController) {
            return appController.currentExpectedCount;
        }
        return 0;
    }

    // ==================== TCP 点检数据包接收脉冲动画 ====================
    Connections {
        target: (typeof appController !== "undefined") ? appController : null
        function onLastTcpMessageChanged() {
            if (appController && appController.lastTcpMessage && appController.lastTcpMessage.length > 0) {
                tcpPulseTimer.restart();
                statusBar.tcpPacketPulse = true;
            }
        }
        function onStatusMessageChanged() {
            // 当后端产生新通知时重置覆盖态以展示最新系统通知
            if (appController && appController.statusMessage && appController.statusMessage.length > 0) {
                statusBar.overrideStatusMessage = appController.statusMessage;
            }
        }
    }

    Timer {
        id: tcpPulseTimer
        interval: 650
        onTriggered: statusBar.tcpPacketPulse = false
    }

    // 复制反馈计时器
    property bool copiedFeedback: false
    Timer {
        id: copyFeedbackTimer
        interval: 1500
        onTriggered: statusBar.copiedFeedback = false
    }

    // ==================== 状态栏主容器 ====================
    RowLayout {
        id: statusRow
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        // ---------------------------------------------------------------------
        // 1. 左侧：动态业务事件与操作提示流 (Live Operational Message Ticker)
        // ---------------------------------------------------------------------
        Rectangle {
            id: messageContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            color: {
                if (messageMouse.containsMouse) return Theme.bgCardElevated;
                if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                    return Qt.rgba(239/255, 68/255, 68/255, 0.16);
                }
                if (statusBar.operationalMessageLevel === "ERROR") {
                    return Qt.rgba(239/255, 68/255, 68/255, 0.12);
                }
                if (statusBar.operationalMessageLevel === "WARN") {
                    return Qt.rgba(245/255, 158/255, 11/255, 0.12);
                }
                return "transparent";
            }
            border.width: (statusBar.operationalMessageLevel !== "INFO") ? 1 : 0
            border.color: {
                if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                    return Qt.rgba(239/255, 68/255, 68/255, 0.45);
                }
                if (statusBar.operationalMessageLevel === "ERROR") {
                    return Qt.rgba(239/255, 68/255, 68/255, 0.35);
                }
                if (statusBar.operationalMessageLevel === "WARN") {
                    return Qt.rgba(245/255, 158/255, 11/255, 0.35);
                }
                return "transparent";
            }
            radius: Theme.radiusSm

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animFast
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 6

                // 极简微引导标 / 状态告警标
                Text {
                    text: statusBar.copiedFeedback ? "✓" : statusBar.operationalIconText
                    color: statusBar.copiedFeedback ? Theme.okLight : statusBar.operationalIconColor
                    font.pixelSize: (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL" || statusBar.operationalMessageLevel === "WARN") ? 12 : 11
                    font.family: Theme.fontMono
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    id: messageLabel
                    Layout.fillWidth: true
                    text: statusBar.copiedFeedback ? "已复制状态信息到剪贴板" : statusBar.operationalMessageText
                    color: statusBar.copiedFeedback ? Theme.okLight : statusBar.operationalMessageColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontCaption
                    font.weight: (statusBar.copiedFeedback || statusBar.operationalMessageLevel !== "INFO") ? Theme.weightMedium : Theme.weightNormal
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }

                // 日志告警/错误一键清除按钮（非致命服务宕机状态下可清除，恢复常规提示流）
                Rectangle {
                    id: dismissBtn
                    visible: statusBar.activeWarnOrErrorLog !== null && !statusBar.hasFatalServiceFault
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: dismissMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.15) : "transparent"
                    radius: 9
                    z: 10

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 10
                        color: dismissMouse.containsMouse ? Theme.textPrimary : Theme.textMuted
                    }

                    MouseArea {
                        id: dismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof appController !== "undefined" && appController && appController.clearLatestWarnOrError) {
                                appController.clearLatestWarnOrError();
                            }
                        }
                    }

                    ToolTip.visible: dismissMouse.containsMouse
                    ToolTip.delay: 300
                    ToolTip.text: "清除此条告警，恢复常规提示流"
                }
            }

            MouseArea {
                id: messageMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                z: 1
                onClicked: {
                    var textToCopy = statusBar.operationalMessageText;
                    if (typeof appController !== "undefined" && appController && appController.copyToClipboard) {
                        appController.copyToClipboard(textToCopy);
                        statusBar.copiedFeedback = true;
                        copyFeedbackTimer.restart();
                    }
                    var idx = statusBar.findIndexById("tcpdata");
                    statusBar.itemClicked(idx >= 0 ? idx : 2, statusBar.tcpDataItemObj || {
                        modelId: "tcpdata",
                        text: textToCopy
                    });
                }
            }

            ToolTip {
                visible: messageMouse.containsMouse && !dismissMouse.containsMouse
                delay: 350
                background: Rectangle {
                    color: Theme.bgPopup
                    border.color: {
                        if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL" || statusBar.operationalMessageLevel === "ERROR") {
                            return Theme.ng;
                        }
                        if (statusBar.operationalMessageLevel === "WARN") {
                            return Theme.warning;
                        }
                        return Theme.borderMedium;
                    }
                    radius: Theme.radiusSm
                }
                contentItem: ColumnLayout {
                    spacing: 3
                    Text {
                        text: {
                            if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                                return "🚨 致命故障 (FATAL / CRITICAL):";
                            }
                            if (statusBar.operationalMessageLevel === "ERROR") {
                                return "✖ 系统严重错误 (ERROR):";
                            }
                            if (statusBar.operationalMessageLevel === "WARN") {
                                return "⚠ 系统运行警告 (WARN):";
                            }
                            return "最新系统事件 / 操作日志:";
                        }
                        color: {
                            if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL" || statusBar.operationalMessageLevel === "ERROR") {
                                return Theme.ngLight;
                            }
                            if (statusBar.operationalMessageLevel === "WARN") {
                                return Theme.warningLight;
                            }
                            return Theme.textMuted;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Theme.weightBold
                    }
                    Text {
                        text: statusBar.operationalMessageText
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: 500
                    }
                    Text {
                        text: "💡 点击可一键复制该条信息至剪贴板"
                        color: Theme.primaryLight
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ---------------------------------------------------------------------
        // 3. 通用动态扩展项 (兼容 statusItems 中非标扩展项)
        // ---------------------------------------------------------------------
        Repeater {
            model: {
                if (!statusItems || statusItems.length === 0)
                    return [];
                var customList = [];
                for (var i = 0; i < statusItems.length; i++) {
                    var item = statusItems[i];
                    if (item && item.modelId !== "status" && item.modelId !== "tcpstatus" && item.modelId !== "tcpdata") {
                        customList.push({
                            index: i,
                            data: item
                        });
                    }
                }
                return customList;
            }

            delegate: RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    width: 1
                    height: 12
                    color: Theme.divider
                }

                Rectangle {
                    Layout.preferredHeight: 22
                    implicitWidth: customRow.implicitWidth + 14
                    radius: Theme.radiusSm
                    color: customMouse.containsMouse ? Theme.bgCardActive : Theme.bgCardElevated
                    border.width: 1
                    border.color: customMouse.containsMouse ? Theme.borderHover : Theme.borderSubtle

                    RowLayout {
                        id: customRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: modelData.data.iconText || ""
                            color: modelData.data.textColor || Theme.textSecondary
                            font.pixelSize: Theme.fontCaption
                            visible: text.length > 0
                        }

                        Text {
                            text: modelData.data.text || ""
                            color: modelData.data.textColor || Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontCaption
                        }
                    }

                    MouseArea {
                        id: customMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: statusBar.itemClicked(modelData.index, modelData.data)
                        onDoubleClicked: statusBar.itemDoubleClicked(modelData.index, modelData.data)
                    }
                }
            }
        }

        // 垂直细分割线 2
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 12
            color: Theme.divider
        }

        // ---------------------------------------------------------------------
        // 4. 右中：硬件与工业通讯遥测微仪表群 (Telemetry Badges)
        // ---------------------------------------------------------------------
        RowLayout {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter

            // 4.1 TCP 点检通讯信号胶囊
            Rectangle {
                id: tcpTelemetryPill
                Layout.preferredHeight: 22
                implicitWidth: tcpRow.implicitWidth + 14
                radius: Theme.radiusPill
                color: {
                    if (statusBar.tcpPacketPulse)
                        return Theme.primaryGlow;
                    if (tcpPillMouse.containsMouse)
                        return Theme.bgCardActive;
                    return statusBar.tcpRunning ? (Theme.isDark ? "#1210b981" : "#ecfdf5") : (Theme.isDark ? "#18f59e0b" : "#fffbeb");
                }
                border.width: 1
                border.color: {
                    if (statusBar.tcpPacketPulse)
                        return Theme.primary;
                    if (tcpPillMouse.containsMouse)
                        return Theme.borderHover;
                    return statusBar.tcpRunning ? Theme.okBorder : Theme.warningBorder;
                }

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
                    id: tcpRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: statusBar.tcpPacketPulse ? Theme.primaryLight : (statusBar.tcpRunning ? Theme.ok : Theme.warning)
                    }

                    Text {
                        text: "TCP :" + statusBar.tcpPort
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        font.weight: Theme.weightBold
                        color: statusBar.tcpPacketPulse ? Theme.primaryLight : (statusBar.tcpRunning ? Theme.okLight : Theme.warningLight)
                    }
                }

                MouseArea {
                    id: tcpPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var idx = statusBar.findIndexById("tcpstatus");
                        statusBar.itemClicked(idx >= 0 ? idx : 1, statusBar.tcpStatusItemObj || {
                            modelId: "tcpstatus",
                            text: "TCP :" + statusBar.tcpPort
                        });
                    }
                }

                ToolTip {
                    visible: tcpPillMouse.containsMouse
                    delay: 350
                    background: Rectangle {
                        color: Theme.bgPopup
                        border.color: Theme.borderMedium
                        radius: Theme.radiusSm
                    }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text {
                            text: "TCP 点检触发通信服务"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightBold
                            color: Theme.textPrimary
                        }
                        Text {
                            text: "服务状态: " + (statusBar.tcpRunning ? "🟢 正常监听中" : "🟠 服务未运行/异常")
                            color: statusBar.tcpRunning ? Theme.okLight : Theme.warningLight
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            text: "监听端口: " + statusBar.tcpPort
                            color: Theme.textSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                        Text {
                            text: statusBar.lastTcpMsg.length > 0 ? ("最近点检报文: " + statusBar.lastTcpMsg) : "暂无点检报文 (等待外部 PLC 信号)"
                            color: statusBar.lastTcpMsg.length > 0 ? Theme.primaryLight : Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // 4.2 FTP 图像接收通道胶囊
            Rectangle {
                id: ftpTelemetryPill
                Layout.preferredHeight: 22
                implicitWidth: ftpRow.implicitWidth + 14
                radius: Theme.radiusPill
                color: {
                    if (ftpPillMouse.containsMouse)
                        return Theme.bgCardActive;
                    return statusBar.ftpRunning ? (Theme.isDark ? "#1210b981" : "#ecfdf5") : (Theme.isDark ? "#18f59e0b" : "#fffbeb");
                }
                border.width: 1
                border.color: {
                    if (ftpPillMouse.containsMouse)
                        return Theme.borderHover;
                    return statusBar.ftpRunning ? Theme.okBorder : Theme.warningBorder;
                }

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
                    id: ftpRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: statusBar.ftpRunning ? Theme.ok : Theme.warning
                    }

                    Text {
                        text: "FTP :" + statusBar.ftpPort + (statusBar.ftpClientCount > 0 ? (" (" + statusBar.ftpClientCount + "连)") : "")
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        font.weight: Theme.weightBold
                        color: statusBar.ftpRunning ? Theme.okLight : Theme.warningLight
                    }
                }

                MouseArea {
                    id: ftpPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }

                ToolTip {
                    visible: ftpPillMouse.containsMouse
                    delay: 350
                    background: Rectangle {
                        color: Theme.bgPopup
                        border.color: Theme.borderMedium
                        radius: Theme.radiusSm
                    }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text {
                            text: "FTP 图像上传接收服务"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.weightBold
                            color: Theme.textPrimary
                        }
                        Text {
                            text: "服务状态: " + (statusBar.ftpRunning ? "🟢 正常运行中" : "🟠 服务未就绪")
                            color: statusBar.ftpRunning ? Theme.okLight : Theme.warningLight
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            text: "监听端口: " + statusBar.ftpPort + " · 活跃上传客户端: " + statusBar.ftpClientCount
                            color: Theme.textSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // 4.3 实时批次监测胶囊 (当有点检批次时动态显现)
            Rectangle {
                visible: statusBar.currentRound > 0
                Layout.preferredHeight: 22
                implicitWidth: batchProgressRow.implicitWidth + 12
                radius: Theme.radiusPill
                color: Theme.primaryGlow
                border.width: 1
                border.color: Theme.primary

                RowLayout {
                    id: batchProgressRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "轮 " + statusBar.currentRound
                        color: Theme.primaryLight
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        font.weight: Theme.weightBold
                    }

                    Text {
                        text: "[" + statusBar.currentCopied + "/" + statusBar.currentExpected + "]"
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                }
            }
        }

        // 垂直细分割线 3
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 12
            color: Theme.divider
        }

        // ---------------------------------------------------------------------
        // 5. 最右侧：工业级高精实时时钟与日期仪表 (Precision Clock & Date Widget)
        // ---------------------------------------------------------------------
        Rectangle {
            id: dateTimePill
            Layout.preferredHeight: 22
            implicitWidth: dateTimeRow.implicitWidth + 14
            radius: Theme.radiusPill
            color: dateTimeMouse.containsMouse ? Theme.bgCardActive : Theme.bgCardElevated
            border.width: 1
            border.color: dateTimeMouse.containsMouse ? Theme.borderHover : Theme.borderSubtle
            Layout.alignment: Qt.AlignVCenter

            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                id: dateTimeRow
                anchors.centerIn: parent
                spacing: 6

                // 极简日历/时钟微图标
                AppIcon {
                    name: "icon_calendar"
                    size: 12
                    color: Theme.textMuted
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    id: statusDateText
                    text: "2026-09-06"
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    width: 1
                    height: 10
                    color: Theme.divider
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    id: statusTimeText
                    text: "00:00:00"
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: Theme.weightBold
                    color: Theme.primaryLight
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: dateTimeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor
            }

            ToolTip {
                visible: dateTimeMouse.containsMouse
                delay: 350
                background: Rectangle {
                    color: Theme.bgPopup
                    border.color: Theme.borderMedium
                    radius: Theme.radiusSm
                }
                contentItem: ColumnLayout {
                    spacing: 2
                    Text {
                        text: "工控机系统时间 (本地标准时间)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.weightBold
                        color: Theme.textPrimary
                    }
                    Text {
                        text: "当前日期: " + statusDateText.text + " " + statusTimeText.text
                        color: Theme.primaryLight
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ===== 状态栏高精时钟刷新定时器 =====
    Timer {
        id: statusClockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: updateStatusClock()
    }

    function updateStatusClock() {
        var now = new Date();
        var year = now.getFullYear();
        var month = String(now.getMonth() + 1).padStart(2, '0');
        var day = String(now.getDate()).padStart(2, '0');
        statusDateText.text = year + "-" + month + "-" + day;

        var hours = String(now.getHours()).padStart(2, '0');
        var minutes = String(now.getMinutes()).padStart(2, '0');
        var seconds = String(now.getSeconds()).padStart(2, '0');
        statusTimeText.text = hours + ":" + minutes + ":" + seconds;
    }

    Component.onCompleted: updateStatusClock()

    // =========================================================================
    // 6. 对外 API 兼容层 (保持 100% 现有方法签名与行为完整兼容)
    // =========================================================================
    function updateItem(index, newData) {
        if (index >= 0 && index < statusItems.length) {
            var newItems = statusItems.slice();
            var obj = Object.assign({}, newItems[index]);
            for (var key in newData) {
                obj[key] = newData[key];
            }
            newItems[index] = obj;
            statusItems = newItems;
        }
    }

    function updateText(index, text) {
        updateItem(index, {
            text: text
        });
    }

    function updateColor(index, color) {
        updateItem(index, {
            textColor: color
        });
    }

    function updateIcon(index, icon) {
        updateItem(index, {
            iconText: icon
        });
    }

    function updateById(modelId, newData) {
        var newItems = statusItems.slice();
        for (var i = 0; i < newItems.length; i++) {
            if (newItems[i].modelId === modelId) {
                var obj = Object.assign({}, newItems[i]);
                for (var key in newData) {
                    obj[key] = newData[key];
                }
                newItems[i] = obj;
                statusItems = newItems;
                return true;
            }
        }
        return false;
    }

    function updateTextById(modelId, text) {
        return updateById(modelId, {
            text: text
        });
    }

    function updateColorById(modelId, color) {
        return updateById(modelId, {
            textColor: color
        });
    }

    function updateIconById(modelId, icon) {
        return updateById(modelId, {
            iconText: icon
        });
    }

    function getItemById(modelId) {
        return findItem(modelId);
    }

    function findItem(modelId) {
        if (!statusItems || !statusItems.length)
            return null;
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i] && statusItems[i].modelId === modelId) {
                return statusItems[i];
            }
        }
        return null;
    }

    function findIndexById(modelId) {
        if (!statusItems || !statusItems.length)
            return -1;
        for (var i = 0; i < statusItems.length; i++) {
            if (statusItems[i] && statusItems[i].modelId === modelId) {
                return i;
            }
        }
        return -1;
    }

    function addItem(itemData) {
        var newItems = statusItems.slice();
        newItems.push(itemData);
        statusItems = newItems;
    }

    function removeItemById(modelId) {
        var newItems = statusItems.slice();
        for (var i = 0; i < newItems.length; i++) {
            if (newItems[i] && newItems[i].modelId === modelId) {
                newItems.splice(i, 1);
                statusItems = newItems;
                return true;
            }
        }
        return false;
    }

    function clearItems() {
        statusItems = [];
    }

    function updateStatus(text) {
        overrideStatusMessage = text;
        updateById("tcpdata", {
            text: text
        });
        if (statusItems.length > 0 && statusItems[0] && statusItems[0].modelId !== "status") {
            updateText(0, text);
        }
    }
}
