import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."
import "common"

Rectangle {
    id: statusBar
    width: parent ? parent.width : 800
    height: 32
    color: Theme.surface
    border.width: 0

    // ==================== 顶部发光微边框与层次 ====================
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.borderMuted
    }

    // ==================== 对外属性 (保持 100% 架构向下兼容) ====================
    property var statusItems: []

    // 默认样式
    property color backgroundColor: Theme.surface
    property color borderColor: Theme.borderMuted
    property color textColor: Theme.textSoft
    property int defaultItemWidth: 0

    // 动态运行期覆盖状态消息
    property string overrideStatusMessage: ""

    // 信号
    signal itemClicked(int index, var itemData)
    signal itemDoubleClicked(int index, var itemData)

    // ==================== 智能解析状态项 ====================
    readonly property var statusItemObj: findItem("status")

    readonly property string systemStatusText: {
        // 1. 如果子页面 Loader 正在加载，优先反映加载状态
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).indexOf("加载") >= 0) {
            return String(statusItemObj.text);
        }
        // 2. 真实服务健康度感知：杜绝服务异常时盲目显示“系统就绪”
        if (!statusBar.tcpRunning) {
            return "TCP 异常";
        }
        if (!statusBar.ftpRunning) {
            return "FTP 异常";
        }
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).length > 0) {
            return String(statusItemObj.text);
        }
        return "系统就绪";
    }

    readonly property color systemStatusColor: {
        if (statusItemObj && statusItemObj.text !== undefined && String(statusItemObj.text).indexOf("加载") >= 0) {
            return Theme.warn;
        }
        if (!statusBar.tcpRunning || !statusBar.ftpRunning) {
            return Theme.warn;
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

    // 致命服务是否异常：FTP 或 TCP 异常属于故障
    readonly property bool hasFatalServiceFault: !statusBar.ftpRunning || !statusBar.tcpRunning

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
        // 1. 最高优先级：服务异常
        if (!statusBar.tcpRunning) {
            return "【服务故障】TCP数据接收服务未运行或端口冲突！无法接收测量数据";
        }
        if (!statusBar.ftpRunning) {
            return "【致命故障】FTP图像接收服务未运行或端口冲突！无法接收检测机台上传的轮对图像";
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
        if (typeof appController !== "undefined" && appController && appController.statusMessage && appController.statusMessage.length > 0) {
            return appController.statusMessage;
        }
        return "就绪 · 工业级高精检测流水线待命";
    }

    readonly property color operationalMessageColor: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL" || operationalMessageLevel === "ERROR") {
            return Theme.danger;
        }
        if (operationalMessageLevel === "WARN") {
            return Theme.warn;
        }
        return Theme.textSoft;
    }

    readonly property color operationalIconColor: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL" || operationalMessageLevel === "ERROR") {
            return Theme.danger;
        }
        if (operationalMessageLevel === "WARN") {
            return Theme.warn;
        }
        return Theme.muted;
    }

    readonly property string operationalIconName: {
        if (operationalMessageLevel === "FATAL" || operationalMessageLevel === "CRITICAL" || operationalMessageLevel === "ERROR") {
            return "icon_error";
        }
        if (operationalMessageLevel === "WARN") {
            return "icon_warning";
        }
        return "icon_info";
    }

    // 硬件与服务遥测数据
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

    readonly property bool tcpRunning: {
        if (typeof appController !== "undefined" && appController) {
            return appController.tcpRunning;
        }
        return true;
    }

    readonly property int tcpPort: {
        if (typeof appController !== "undefined" && appController && appController.tcpPort > 0) {
            return appController.tcpPort;
        }
        return 9000;
    }

    readonly property int tcpClientCount: {
        if (typeof appController !== "undefined" && appController) {
            return appController.tcpClientCount;
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

    // ==================== 状态通知监听 ====================
    Connections {
        target: (typeof appController !== "undefined") ? appController : null
        function onStatusMessageChanged() {
            // 当后端产生新通知时重置覆盖态以展示最新系统通知
            if (appController && appController.statusMessage && appController.statusMessage.length > 0) {
                statusBar.overrideStatusMessage = appController.statusMessage;
            }
        }
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
                if (messageMouse.containsMouse) return Theme.surfaceAlt;
                if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                    return Theme.dangerSoft;
                }
                if (statusBar.operationalMessageLevel === "ERROR") {
                    return Theme.dangerSoft;
                }
                if (statusBar.operationalMessageLevel === "WARN") {
                    return Theme.warnSoft;
                }
                return "transparent";
            }
            border.width: (statusBar.operationalMessageLevel !== "INFO") ? 1 : 0
            border.color: {
                if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                    return Theme.dangerBorder;
                }
                if (statusBar.operationalMessageLevel === "ERROR") {
                    return Theme.dangerBorder;
                }
                if (statusBar.operationalMessageLevel === "WARN") {
                    return Theme.warnBorder;
                }
                return "transparent";
            }
            radius: Theme.radiusMicro

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
                AppIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: statusBar.copiedFeedback ? "icon_check" : statusBar.operationalIconName
                    size: 14
                    color: statusBar.copiedFeedback ? Theme.ok : statusBar.operationalIconColor
                }

                Text {
                    id: messageLabel
                    Layout.fillWidth: true
                    text: statusBar.copiedFeedback ? "已复制状态信息到剪贴板" : statusBar.operationalMessageText
                    color: statusBar.copiedFeedback ? Theme.ok : statusBar.operationalMessageColor
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontCaption
                    font.weight: (statusBar.copiedFeedback || statusBar.operationalMessageLevel !== "INFO") ? Theme.fontMedium : Theme.fontRegular
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
                    color: dismissMouse.containsMouse ? Theme.hover : "transparent"
                    radius: Theme.radiusPill
                    z: 10

                    AppIcon {
                        anchors.centerIn: parent
                        name: "icon_close"
                        size: 12
                        color: dismissMouse.containsMouse ? Theme.text : Theme.muted
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
                    statusBar.itemClicked(0, {
                        modelId: "message",
                        text: textToCopy
                    });
                }
            }

            ToolTip {
                visible: messageMouse.containsMouse && !dismissMouse.containsMouse
                delay: 350
                background: Rectangle {
                    color: Theme.surfaceFloating
                    border.color: {
                        if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL" || statusBar.operationalMessageLevel === "ERROR") {
                            return Theme.danger;
                        }
                        if (statusBar.operationalMessageLevel === "WARN") {
                            return Theme.warn;
                        }
                        return Theme.border;
                    }
                    radius: Theme.radiusMicro
                }
                contentItem: ColumnLayout {
                    spacing: 3
                    Text {
                        text: {
                            if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL") {
                                return "致命故障 (FATAL / CRITICAL):";
                            }
                            if (statusBar.operationalMessageLevel === "ERROR") {
                                return "系统严重错误 (ERROR):";
                            }
                            if (statusBar.operationalMessageLevel === "WARN") {
                                return "系统运行警告 (WARN):";
                            }
                            return "最新系统事件 / 操作日志:";
                        }
                        color: {
                            if (statusBar.operationalMessageLevel === "FATAL" || statusBar.operationalMessageLevel === "CRITICAL" || statusBar.operationalMessageLevel === "ERROR") {
                                return Theme.danger;
                            }
                            if (statusBar.operationalMessageLevel === "WARN") {
                                return Theme.warn;
                            }
                            return Theme.muted;
                        }
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.fontMedium
                    }
                    Text {
                        text: statusBar.operationalMessageText
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontCaption
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: 500
                    }
                    Text {
                        text: "点击可一键复制该条信息至剪贴板"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
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
                    if (item && item.modelId !== "status") {
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
                    color: Theme.borderMuted
                }

                Rectangle {
                    Layout.preferredHeight: 22
                    implicitWidth: customRow.implicitWidth + 14
                    radius: Theme.radiusMicro
                    color: customMouse.containsMouse ? Theme.pressed : Theme.surfaceAlt
                    border.width: 1
                    border.color: customMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted

                    RowLayout {
                        id: customRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: modelData.data.iconText || ""
                            color: modelData.data.textColor || Theme.textSoft
                            font.pixelSize: Theme.fontCaption
                            visible: text.length > 0
                        }

                        Text {
                            text: modelData.data.text || ""
                            color: modelData.data.textColor || Theme.textSoft
                            font.family: Theme.fontSans
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
            color: Theme.borderMuted
        }

        // ---------------------------------------------------------------------
        // 4. 右中：硬件与工业通讯遥测微仪表群 (Telemetry Badges)
        // ---------------------------------------------------------------------
        RowLayout {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter

            // 4.1 TCP 数据通道胶囊
            Rectangle {
                id: tcpTelemetryPill
                Layout.preferredHeight: 22
                implicitWidth: tcpRow.implicitWidth + 14
                radius: Theme.radiusPill
                color: {
                    if (tcpPillMouse.containsMouse)
                        return Theme.pressed;
                    return statusBar.tcpRunning ? Theme.okSoft : Theme.warnSoft;
                }
                border.width: 1
                border.color: {
                    if (tcpPillMouse.containsMouse)
                        return Theme.borderStrong;
                    return statusBar.tcpRunning ? Theme.okBorder : Theme.warnBorder;
                }

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    id: tcpRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: Theme.radiusPill
                        color: statusBar.tcpRunning ? Theme.ok : Theme.warn
                    }

                    Text {
                        text: "TCP :" + statusBar.tcpPort + (statusBar.tcpClientCount > 0 ? (" (" + statusBar.tcpClientCount + "连)") : "")
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.fontMedium
                        color: statusBar.tcpRunning ? Theme.ok : Theme.warn
                    }
                }

                MouseArea {
                    id: tcpPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }

                ToolTip {
                    visible: tcpPillMouse.containsMouse
                    delay: 350
                    background: Rectangle {
                        color: Theme.surfaceFloating
                        border.color: Theme.border
                        radius: Theme.radiusMicro
                    }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text {
                            text: "TCP 数据接收服务 (检测数据流)"
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.fontMedium
                            color: Theme.text
                        }
                        Text {
                            text: "服务状态: " + (statusBar.tcpRunning ? "正常监听中" : "服务未就绪")
                            color: statusBar.tcpRunning ? Theme.ok : Theme.warn
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                        Text {
                            text: "监听端口: " + statusBar.tcpPort + " · 活跃客户端: " + statusBar.tcpClientCount
                            color: Theme.textSoft
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.pixelSize: Theme.fontCaption
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
                        return Theme.pressed;
                    return statusBar.ftpRunning ? Theme.okSoft : Theme.warnSoft;
                }
                border.width: 1
                border.color: {
                    if (ftpPillMouse.containsMouse)
                        return Theme.borderStrong;
                    return statusBar.ftpRunning ? Theme.okBorder : Theme.warnBorder;
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
                        radius: Theme.radiusPill
                        color: statusBar.ftpRunning ? Theme.ok : Theme.warn
                    }

                    Text {
                        text: "FTP :" + statusBar.ftpPort + (statusBar.ftpClientCount > 0 ? (" (" + statusBar.ftpClientCount + "连)") : "")
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.fontMedium
                        color: statusBar.ftpRunning ? Theme.ok : Theme.warn
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
                        color: Theme.surfaceFloating
                        border.color: Theme.border
                        radius: Theme.radiusMicro
                    }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Text {
                            text: "FTP 图像上传接收服务"
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                            font.weight: Theme.fontMedium
                            color: Theme.text
                        }
                        Text {
                            text: "服务状态: " + (statusBar.ftpRunning ? "正常运行中" : "服务未就绪")
                            color: statusBar.ftpRunning ? Theme.ok : Theme.warn
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontCaption
                        }
                        Text {
                            text: "监听端口: " + statusBar.ftpPort + " · 活跃上传客户端: " + statusBar.ftpClientCount
                            color: Theme.textSoft
                            font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                            font.pixelSize: Theme.fontCaption
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
                color: Theme.activeSubtle
                border.width: 1
                border.color: Theme.accent

                RowLayout {
                    id: batchProgressRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "轮 " + statusBar.currentRound
                        color: Theme.text
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                        font.weight: Theme.fontMedium
                    }

                    Text {
                        text: "[" + statusBar.currentCopied + "/" + statusBar.currentExpected + "]"
                        color: Theme.text
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontMicro
                    }
                }
            }
        }

        // 垂直细分割线 3
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 12
            color: Theme.borderMuted
        }

        // ---------------------------------------------------------------------
        // 5. 最右侧：工业级高精实时时钟与日期仪表 (Precision Clock & Date Widget)
        // ---------------------------------------------------------------------
        Rectangle {
            id: dateTimePill
            Layout.preferredHeight: 22
            implicitWidth: dateTimeRow.implicitWidth + 14
            radius: Theme.radiusPill
            color: dateTimeMouse.containsMouse ? Theme.pressed : Theme.surfaceAlt
            border.width: 1
            border.color: dateTimeMouse.containsMouse ? Theme.borderStrong : Theme.borderMuted
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
                    color: Theme.muted
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    id: statusDateText
                    text: "2026-09-06"
                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                    font.pixelSize: Theme.fontMicro
                    color: Theme.textSoft
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    width: 1
                    height: 10
                    color: Theme.borderMuted
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    id: statusTimeText
                    text: "00:00:00"
                    font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                    font.pixelSize: Theme.fontMicro
                    font.weight: Theme.fontMedium
                    color: Theme.text
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
                    color: Theme.surfaceFloating
                    border.color: Theme.border
                    radius: Theme.radiusMicro
                }
                contentItem: ColumnLayout {
                    spacing: 2
                    Text {
                        text: "工控机系统时间 (本地标准时间)"
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.fontCaption
                        font.weight: Theme.fontMedium
                        color: Theme.text
                    }
                    Text {
                        text: "当前日期: " + statusDateText.text + " " + statusTimeText.text
                        color: Theme.text
                        font.family: Theme.fontSans; font.features: Theme.fontFeaturesTabular
                        font.pixelSize: Theme.fontCaption
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
        if (statusItems.length > 0 && statusItems[0] && statusItems[0].modelId !== "status") {
            updateText(0, text);
        }
    }
}
