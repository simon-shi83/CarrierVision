import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    // 分页与数据状态
    property int currentPage: 1
    property int pageSize: 50
    property int totalCount: 0
    property int totalPages: 1
    property int logRequestId: -1
    property var logItems: []
    property var logStats: ({})
    property var availableDates: []

    function refreshData() {
        if (!appController) return

        // 1. 刷新统计指标
        // Statistics are returned with the asynchronous query.

        // 2. 刷新可用日期列表
        var dates = appController.getAvailableLogDates()
        availableDates = dates
        if (dateCombo.currentIndex < 0 || dateCombo.currentIndex >= dates.length) {
            dateCombo.currentIndex = 0
        }

        // 3. 执行查询
        queryCurrentPage()
    }

    function queryCurrentPage() {
        if (!appController) return
        var dStr = (availableDates && availableDates.length > dateCombo.currentIndex && dateCombo.currentIndex >= 0)
                   ? availableDates[dateCombo.currentIndex] : ""
        var lvl = levelCombo.currentValue || "all"
        var kw = searchField.text.trim()

        logRequestId = appController.requestLogs(dStr, lvl, kw, currentPage, pageSize)
    }

    function filterByLevel(lvl) {
        var lower = String(lvl).toLowerCase();
        for (var i = 0; i < levelCombo.model.length; i++) {
            if (levelCombo.model[i].value === lower) {
                levelCombo.currentIndex = i;
                break;
            }
        }
        currentPage = 1;
        queryCurrentPage();
    }

    Connections {
        target: appController
        function onLogQueryFinished(requestId, res) {
            if (requestId !== root.logRequestId) return
            root.totalCount = res.total || 0
            root.totalPages = res.totalPages || 1
            root.currentPage = res.page || 1
            root.logItems = res.items || []
            root.logStats = res.stats || {}
        }
    }

    Component.onCompleted: {
        refreshData()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // ==================== 1. 顶部：工业监控统计看板 ====================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // 卡片 1: 今日总日志数
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        width: 42; height: 42; radius: Theme.radiusMd
                        color: Theme.primaryGlow
                        AppIcon { anchors.centerIn: parent; name: "nav_log"; size: 22; color: Theme.primary }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text { text: "今日日志总数"; font.pixelSize: Theme.fontSizeSmall; color: Theme.textSecondary; font.family: Theme.fontFamily }
                        Text { text: String(root.logStats.todayTotal || 0); font.pixelSize: 20; font.bold: true; color: Theme.textPrimary; font.family: Theme.fontMono }
                    }
                }
            }

            // 卡片 2: 今日异常/警告
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        width: 42; height: 42; radius: Theme.radiusMd
                        color: Theme.warningBg
                        AppIcon { anchors.centerIn: parent; name: "nav_alert"; size: 22; color: Theme.warning }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text { text: "今日系统警告"; font.pixelSize: Theme.fontSizeSmall; color: Theme.textSecondary; font.family: Theme.fontFamily }
                        Text { text: String(root.logStats.todayWarn || 0); font.pixelSize: 20; font.bold: true; color: Theme.warning; font.family: Theme.fontMono }
                    }
                }
            }

            // 卡片 3: 今日严重错误
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        width: 42; height: 42; radius: Theme.radiusMd
                        color: Theme.ngBg
                        Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 20; font.bold: true; color: Theme.ng }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text { text: "今日严重错误"; font.pixelSize: Theme.fontSizeSmall; color: Theme.textSecondary; font.family: Theme.fontFamily }
                        Text { text: String(root.logStats.todayError || 0); font.pixelSize: 20; font.bold: true; color: Theme.ng; font.family: Theme.fontMono }
                    }
                }
            }

            // 卡片 4: 日志磁盘总占用 (满 1GB 自动淘汰最老文件)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        width: 42; height: 42; radius: Theme.radiusMd
                        color: Theme.okBg
                        AppIcon { anchors.centerIn: parent; name: "icon_file_text"; size: 22; color: Theme.ok }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text { text: "日志磁盘占用 (上限 1 GB)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.textSecondary; font.family: Theme.fontFamily }
                        RowLayout {
                            spacing: 6
                            Text { text: String(root.logStats.totalSizeStr || "0 MB"); font.pixelSize: 18; font.bold: true; color: Theme.textPrimary; font.family: Theme.fontMono }
                            Text { text: "· 共 " + String(root.logStats.fileCount || 0) + " 个文件"; font.pixelSize: 12; color: Theme.textMuted }
                        }
                    }
                }
            }
        }

        // ==================== 2. 组合查询与操作工具栏 ====================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: Theme.radiusMd
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.borderMedium

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                // 日期筛选
                RowLayout {
                    spacing: 8
                    Text {
                        text: "日志日期:"
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                    ComboBox {
                        id: dateCombo
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 34
                        model: root.availableDates
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall

                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: Theme.bgInput
                            border.color: dateCombo.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                            border.width: 1
                        }

                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: 26
                            text: dateCombo.currentText
                            color: Theme.textPrimary
                            font: dateCombo.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: AppIcon {
                            x: dateCombo.width - width - 8
                            y: (dateCombo.height - height) / 2
                            name: "icon_arrow_down"
                            size: 12
                            color: Theme.textSecondary
                        }

                        popup: Popup {
                            y: dateCombo.height + 4
                            width: Math.max(dateCombo.width, 160)
                            implicitHeight: Math.min(260, contentItem.implicitHeight + 8)
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
                                model: dateCombo.popup.visible ? dateCombo.delegateModel : null
                                currentIndex: dateCombo.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }

                        delegate: ItemDelegate {
                            width: dateCombo.width - 8
                            height: 32
                            contentItem: Text {
                                text: modelData
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: highlighted ? Theme.bgCardActive : "transparent"
                            }
                        }

                        onActivated: {
                            root.currentPage = 1
                            root.queryCurrentPage()
                        }
                    }
                }

                // 级别筛选
                RowLayout {
                    spacing: 8
                    Text {
                        text: "日志级别:"
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                    ComboBox {
                        id: levelCombo
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 34
                        textRole: "text"
                        valueRole: "value"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        model: [
                            { text: "全部级别", value: "all" },
                            { text: "INFO 信息", value: "info" },
                            { text: "WARN 警告", value: "warn" },
                            { text: "ERROR 错误", value: "error" },
                            { text: "DEBUG 调试", value: "debug" }
                        ]

                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: Theme.bgInput
                            border.color: levelCombo.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                            border.width: 1
                        }

                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: 26
                            text: levelCombo.currentText
                            color: Theme.textPrimary
                            font: levelCombo.font
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: AppIcon {
                            x: levelCombo.width - width - 8
                            y: (levelCombo.height - height) / 2
                            name: "icon_arrow_down"
                            size: 12
                            color: Theme.textSecondary
                        }

                        popup: Popup {
                            y: levelCombo.height + 4
                            width: levelCombo.width
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
                                model: levelCombo.popup.visible ? levelCombo.delegateModel : null
                                currentIndex: levelCombo.highlightedIndex
                            }
                        }

                        delegate: ItemDelegate {
                            width: levelCombo.width - 8
                            height: 32
                            contentItem: Text {
                                text: modelData.text
                                color: {
                                    if (modelData.value === "error") return Theme.ng
                                    if (modelData.value === "warn") return Theme.warning
                                    if (modelData.value === "info") return Theme.ok
                                    return Theme.textPrimary
                                }
                                font.bold: highlighted || modelData.value === levelCombo.currentValue
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: highlighted ? Theme.bgCardActive : "transparent"
                            }
                        }

                        onActivated: {
                            root.currentPage = 1
                            root.queryCurrentPage()
                        }
                    }
                }

                // 关键字搜索
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        placeholderText: "输入关键字搜索日志内容或时间..."
                        placeholderTextColor: Theme.textMuted
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        selectByMouse: true
                        background: Rectangle {
                            color: Theme.bgInput
                            radius: Theme.radiusSm
                            border.color: searchField.activeFocus ? Theme.borderHighlight : Theme.borderSubtle
                            border.width: 1
                        }
                        onAccepted: {
                            root.currentPage = 1
                            root.queryCurrentPage()
                        }
                    }
                }

                // 查询按钮
                ActionButton {
                    Layout.preferredHeight: 34
                    Layout.preferredWidth: 76
                    text: "查询"
                    variant: "primary"
                    onClicked: {
                        root.currentPage = 1
                        root.queryCurrentPage()
                    }
                }

                // 刷新按钮
                ActionButton {
                    Layout.preferredHeight: 34
                    Layout.preferredWidth: 76
                    text: "刷新"
                    variant: "secondary"
                    onClicked: root.refreshData()
                }

                // 打开日志目录按钮
                ActionButton {
                    Layout.preferredHeight: 34
                    Layout.preferredWidth: 124
                    text: "📁 打开日志目录"
                    variant: "secondary"
                    onClicked: {
                        if (appController) appController.openLogDirectory()
                    }
                }
            }
        }

        // ==================== 3. 日志数据展示表格 ====================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMd
            color: Theme.bgCard
            border.width: 1
            border.color: Theme.borderMedium
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // 表头
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.bgCardElevated

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text { Layout.preferredWidth: 50; text: "#"; font.bold: true; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        Text { Layout.preferredWidth: 170; text: "时间戳"; font.bold: true; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        Text { Layout.preferredWidth: 80; text: "级别"; font.bold: true; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; horizontalAlignment: Text.AlignHCenter }
                        Text { Layout.fillWidth: true; text: "日志消息正文"; font.bold: true; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: Theme.borderSubtle
                    }
                }

                // 列表内容
                ListView {
                    id: logListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.logItems
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: delegateRow
                        width: logListView.width
                        height: 38
                        color: index % 2 === 0 ? "transparent" : (Theme.isDark ? "#09ffffff" : "#05000000")

                        // 整个数据行的指针悬停检测
                        HoverHandler {
                            id: rowHoverHandler
                        }

                        // 双击打开完整详情弹窗
                        TapHandler {
                            onDoubleTapped: {
                                detailDialog.logDetail = modelData.raw || modelData.message
                                detailDialog.open()
                            }
                        }

                        // 悬停行高亮背景
                        Rectangle {
                            anchors.fill: parent
                            color: (rowHoverHandler.hovered || copyBtn.hovered) ? Theme.bgCardActive : "transparent"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 84 // 固定右侧留白，防止悬停按钮出现时引起布局跳动
                            spacing: 12

                            // 序号
                            Text {
                                Layout.preferredWidth: 50
                                text: String((root.currentPage - 1) * root.pageSize + index + 1)
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }

                            // 时间戳
                            Text {
                                Layout.preferredWidth: 170
                                text: modelData.time || ""
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }

                            // 级别徽章药丸
                            Item {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 22

                                readonly property string lvl: String(modelData.level || "INFO").toUpperCase()

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 64; height: 20; radius: 10
                                    color: {
                                        if (parent.lvl === "ERROR" || parent.lvl === "CRITICAL") return Theme.ngBg
                                        if (parent.lvl === "WARN" || parent.lvl === "WARNING") return Theme.warningBg
                                        if (parent.lvl === "DEBUG" || parent.lvl === "TRACE") return Theme.bgCardElevated
                                        return Theme.okBg
                                    }
                                    border.width: 1
                                    border.color: {
                                        if (parent.lvl === "ERROR" || parent.lvl === "CRITICAL") return Theme.ngBorder
                                        if (parent.lvl === "WARN" || parent.lvl === "WARNING") return Theme.warning
                                        if (parent.lvl === "DEBUG" || parent.lvl === "TRACE") return Theme.borderMedium
                                        return Theme.okBorder
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.lvl
                                        font.bold: true
                                        font.pixelSize: 10
                                        font.family: Theme.fontMono
                                        color: {
                                            if (parent.parent.lvl === "ERROR" || parent.parent.lvl === "CRITICAL") return Theme.ng
                                            if (parent.parent.lvl === "WARN" || parent.parent.lvl === "WARNING") return Theme.warning
                                            if (parent.parent.lvl === "DEBUG" || parent.parent.lvl === "TRACE") return Theme.textMuted
                                            return Theme.ok
                                        }
                                    }
                                }
                            }

                            // 日志正文（支持鼠标划词拖拽选中复制）
                            TextEdit {
                                id: msgEdit
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.message || ""
                                readOnly: true
                                selectByMouse: true
                                activeFocusOnPress: true
                                cursorVisible: false
                                selectionColor: Theme.primaryLight
                                selectedTextColor: "#ffffff"
                                color: {
                                    var l = String(modelData.level || "").toUpperCase()
                                    if (l === "ERROR" || l === "CRITICAL") return Theme.ng
                                    if (l === "WARN" || l === "WARNING") return Theme.warning
                                    return Theme.textPrimary
                                }
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }
                        }

                        // 仅在鼠标悬停到当前行时浮现复制按钮
                        Button {
                            id: copyBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68
                            height: 26
                            z: 10

                            readonly property bool isHovered: rowHoverHandler.hovered || hovered || copied
                            visible: opacity > 0
                            opacity: isHovered ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            property bool copied: false
                            Timer {
                                id: resetTimer
                                interval: 1500
                                onTriggered: copyBtn.copied = false
                            }

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: copyBtn.copied ? "✓" : "📋"
                                    font.pixelSize: 11
                                    color: copyBtn.copied ? Theme.ok : Theme.textSecondary
                                }
                                Text {
                                    text: copyBtn.copied ? "已复制" : "复制"
                                    font.pixelSize: 11
                                    font.bold: copyBtn.copied
                                    color: copyBtn.copied ? Theme.ok : Theme.textPrimary
                                }
                            }

                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: copyBtn.copied ? Theme.okBg : (copyBtn.hovered ? Theme.bgCardActive : Theme.bgCardElevated)
                                border.width: 1
                                border.color: copyBtn.copied ? Theme.okBorder : (copyBtn.hovered ? Theme.borderMedium : Theme.borderSubtle)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                            }

                            onClicked: {
                                var textToCopy = modelData.raw || (modelData.time + " [" + modelData.level + "] " + modelData.message)
                                if (appController && appController.copyToClipboard) {
                                    appController.copyToClipboard(textToCopy)
                                }
                                copied = true
                                resetTimer.restart()
                            }
                        }
                    }

                    // 空数据占位提示
                    Item {
                        anchors.fill: parent
                        visible: root.logItems.length === 0
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "📭 无匹配日志数据"
                                font.pixelSize: 16
                                font.bold: true
                                color: Theme.textSecondary
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "请尝试调整上方日期、级别或关键字筛选条件"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }

        // ==================== 4. 底部状态与分页控制栏 ====================
        PageBar {
            Layout.fillWidth: true
            currentPage: root.currentPage
            totalPages: root.totalPages
            pageSize: root.pageSize
            totalCount: root.totalCount
            pageSizeOptions: [20, 50, 100, 200]
            onPageRequested: function(page, size) {
                root.currentPage = page
                root.pageSize = size
                root.queryCurrentPage()
            }
        }
    }

    // 日志详情弹窗
    Dialog {
        id: detailDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 680
        modal: true
        property string logDetail: ""

        background: Rectangle {
            color: Theme.bgCard
            radius: Theme.radiusMd
            border.color: Theme.borderMedium
            border.width: 1
        }

        header: Rectangle {
            width: parent.width
            height: 44
            color: Theme.bgCardElevated
            radius: Theme.radiusMd

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8

                Rectangle {
                    width: 3
                    height: 14
                    radius: 1.5
                    color: Theme.primary
                }

                Text {
                    text: "日志详情"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "✕"
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    onClicked: detailDialog.close()
                    contentItem: Text {
                        text: parent.text
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: parent.hovered ? Theme.ngBg : "transparent"
                        radius: Theme.radiusSm
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.borderSubtle
            }
        }

        contentItem: ColumnLayout {
            spacing: 12
            TextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 240
                text: detailDialog.logDetail
                readOnly: true
                wrapMode: Text.WrapAnywhere
                font.family: Theme.fontMono
                font.pixelSize: 12
                color: Theme.textPrimary
                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSm
                    border.color: Theme.borderSubtle
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 10
                ActionButton {
                    text: "复制完整内容"
                    variant: "primary"
                    Layout.preferredHeight: 32
                    onClicked: {
                        if (appController && appController.copyToClipboard) {
                            appController.copyToClipboard(detailDialog.logDetail)
                        } else {
                            searchField.text = detailDialog.logDetail
                            searchField.selectAll()
                            searchField.copy()
                        }
                        detailDialog.close()
                    }
                }
                ActionButton {
                    text: "关闭"
                    variant: "secondary"
                    Layout.preferredHeight: 32
                    onClicked: detailDialog.close()
                }
            }
        }
    }
}
