import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Item {
    id: root
    anchors.fill: parent

    // 视图模式: 0 为数据列表(左表右图), 1 为图片画廊(平铺宫格)
    property int viewMode: 0

    // 分页核心状态
    property int currentPage: 1
    property int pageSize: 10
    property int totalPages: 1
    property int totalCount: 0
    property bool shouldSelectFirst: false
    property int searchModelEpoch: 0

    function requestPage(resetToFirst) {
        if (resetToFirst) currentPage = 1
        var start = queryCond.startDate || ""
        var end = queryCond.endDate || ""
        var rack = queryCond.rackno || 0
        var wheel = (queryCond.turno === undefined || queryCond.turno === "全部") ? "" : queryCond.turno
        var resFlag = (queryCond.result === "OK") ? "1" : (queryCond.result === "NG" ? "0" : "")

        if (appController && appController.searchPaged) {
            root.shouldSelectFirst = true
            appController.searchPaged(start, end, queryCond.keyword || "", rack, wheel, resFlag, currentPage, pageSize)
            if (pageBarLoader.item) {
                pageBarLoader.item.currentPage = currentPage
                pageBarLoader.item.pageSize = pageSize
            }
        }
    }

    function openGenericQuery(startDate, endDate, wheelNumber, resultType) {
        root.viewMode = 0
        queryCond.applyQuery(startDate, endDate, wheelNumber, resultType)
    }

    function currentSelectedItem() {
        if (!appController || !appController.searchImagesModel) return null
        if (list.currentIndex < 0 || list.currentIndex >= appController.searchImagesModel.count) return null
        return appController.searchImagesModel.get(list.currentIndex)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 顶栏：组合查询栏 + 右侧模式切换胶囊
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            QueryConditionBar {
                id: queryCond
                Layout.fillWidth: true
                includeResult: true
                onSearchClicked: {
                    root.requestPage(true)
                }
                onResetClicked: {
                    appController.clearSearch()
                }
            }

            // 模式切换胶囊: 数据列表 / 图片画廊
            Rectangle {
                Layout.preferredHeight: 52
                implicitWidth: viewSwitchRow.implicitWidth + 12
                radius: Theme.radiusMd
                color: Theme.bgCard
                border.color: Theme.borderMedium
                border.width: 1

                Row {
                    id: viewSwitchRow
                    anchors.centerIn: parent
                    spacing: 4

                    // [ ≡ 数据列表 ]
                    Rectangle {
                        width: 92
                        height: 38
                        radius: Theme.radiusSm
                        color: root.viewMode === 0 ? Theme.bgCardActive : (btnListMouse.containsMouse ? Theme.bgCardElevated : "transparent")
                        border.width: 1
                        border.color: root.viewMode === 0 ? Theme.primary : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "≡"
                                font.pixelSize: 15
                                font.bold: true
                                color: root.viewMode === 0 ? Theme.primaryLight : Theme.textSecondary
                            }
                            Text {
                                text: "数据列表"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.viewMode === 0
                                color: root.viewMode === 0 ? Theme.textPrimary : Theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: btnListMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.viewMode !== 0) {
                                    root.viewMode = 0
                                    root.pageSize = 10
                                    root.requestPage(true)
                                }
                            }
                        }
                    }

                    // [ ⊞ 图片画廊 ]
                    Rectangle {
                        width: 92
                        height: 38
                        radius: Theme.radiusSm
                        color: root.viewMode === 1 ? Theme.bgCardActive : (btnGalleryMouse.containsMouse ? Theme.bgCardElevated : "transparent")
                        border.width: 1
                        border.color: root.viewMode === 1 ? Theme.primary : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "⊞"
                                font.pixelSize: 14
                                font.bold: true
                                color: root.viewMode === 1 ? Theme.primaryLight : Theme.textSecondary
                            }
                            Text {
                                text: "图片画廊"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.viewMode === 1
                                color: root.viewMode === 1 ? Theme.textPrimary : Theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: btnGalleryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.viewMode !== 1) {
                                    root.viewMode = 1
                                    root.pageSize = 12
                                    root.requestPage(true)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 主体视窗区域：根据 viewMode 切换
        StackLayout {
            id: mainViewStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.viewMode

            // 视图 0：数据列表视图 (左表右图)
            RowLayout {
                spacing: 10

                // 左侧：数据表格卡片
                Rectangle {
                    Layout.preferredWidth: Math.floor(mainViewStack.width * 0.58)
                    Layout.fillHeight: true
                    radius: Theme.radiusLg
                    color: Theme.bgCard
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // 表格固定表头
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color: Theme.bgCardElevated
                            radius: Theme.radiusMd
                            border.color: Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 8

                                Text { text: "时间 / 文件名"; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; Layout.fillWidth: true }
                                Text { text: "架号"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                Text { text: "轮号"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                Text { text: "距离(小)"; Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                Text { text: "距离(大)"; Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                Text { text: "基准"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                Text { text: "判定"; Layout.preferredWidth: 48; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                            }
                        }

                        // 数据行列表
                        ListView {
                            id: list
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: appController ? appController.searchImagesModel : null
                            clip: true
                            spacing: 4

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: itemRect
                                width: list.width
                                height: 42
                                radius: Theme.radiusMd
                                readonly property bool isCurrent: list.currentIndex === index
                                readonly property bool isHovered: mouseArea.containsMouse

                                color: isCurrent 
                                    ? Theme.bgCardActive 
                                    : (isHovered ? Theme.bgCardElevated : (index % 2 === 0 ? "transparent" : (Theme.isDark ? "#06ffffff" : "#03000000")))

                                border.width: 1
                                border.color: isCurrent 
                                    ? Theme.primary 
                                    : (isHovered ? Theme.borderHover : "transparent")

                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: fileName
                                            color: itemRect.isCurrent ? Theme.primaryLight : Theme.textPrimary
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                            elide: Text.ElideMiddle
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: receivedAtText
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontSizeTiny
                                        }
                                    }

                                    Text { text: String(rack); Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textPrimary; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeBody }
                                    Text { text: String(slot); Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textPrimary; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeBody }
                                    Text { text: String(distance); Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeSmall }
                                    Text { text: String(dist_max); Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeSmall }
                                    Text { text: String(dist_norm); Layout.preferredWidth: 44; horizontalAlignment: Text.AlignHCenter; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: Theme.fontSizeSmall }

                                    // 结果判定药丸
                                    Rectangle {
                                        Layout.preferredWidth: 48
                                        Layout.preferredHeight: 24
                                        radius: Theme.radiusSm
                                        color: result === 1 ? Theme.okBg : Theme.ngBg
                                        border.color: result === 1 ? Theme.okBorder : Theme.ngBorder
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: result === 1 ? "OK" : "NG"
                                            color: result === 1 ? Theme.okLight : Theme.ngLight
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: list.currentIndex = index
                                    onDoubleClicked: {
                                        list.currentIndex = index
                                        var item = appController.searchImagesModel.get(index)
                                        if (item && item.fileUrl) {
                                            inspectViewer.openViewer(item.fileUrl, item.fileName, "架 #" + item.rack + " ╎ 轮 #" + item.slot + " ╎ " + item.receivedAtText)
                                        }
                                    }
                                }
                            }

                            onCountChanged: {
                                if (count > 0) Qt.callLater(function() { list.currentIndex = 0; })
                                else list.currentIndex = -1
                            }
                        }
                    }
                }

                // 右侧：高精预览卡片
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusLg
                    color: Theme.bgCard
                    border.width: 1
                    border.color: Theme.borderMedium

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle { width: 3; height: 14; radius: 1.5; color: Theme.primary }
                            Label {
                                text: "点检原图精准检验视窗"
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeH3
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                text: "全屏视窗"
                                variant: "secondary"
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: 80
                                enabled: preview.visible && preview.selectedFileUrl !== ""
                                onClicked: {
                                    if (preview.selectedFileUrl !== "") {
                                        var item = root.currentSelectedItem()
                                        inspectViewer.openViewer(preview.selectedFileUrl, item ? item.fileName : "检测原图", item ? ("架 #" + item.rack + " ╎ 轮 #" + item.slot + " ╎ " + item.receivedAtText) : "")
                                    }
                                }
                            }
                        }

                        // 图像容器
                        Rectangle {
                            id: previewBox
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.bgInput
                            radius: Theme.radiusMd
                            border.color: Theme.borderSubtle
                            border.width: 1
                            clip: true

                            Image {
                                id: preview
                                anchors.fill: parent
                                anchors.margins: 6
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                                smooth: true
                                property string selectedFileUrl: (root.searchModelEpoch >= 0 && root.currentSelectedItem()) ? (root.currentSelectedItem().fileUrl || "") : ""
                                source: selectedFileUrl || ""
                                visible: source !== "" && status === Image.Ready
                            }

                            // 无图提示
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                visible: !preview.visible

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    AppIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        name: "icon_camera"
                                        size: 34
                                        color: Theme.textMuted
                                        opacity: 0.35
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        color: Theme.textMuted
                                        text: "请从左侧列表选择记录进行预览"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: preview.visible ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (preview.selectedFileUrl !== "") {
                                        var item = root.currentSelectedItem()
                                        inspectViewer.openViewer(preview.selectedFileUrl, item ? item.fileName : "检测原图", item ? ("架 #" + item.rack + " ╎ 轮 #" + item.slot + " ╎ " + item.receivedAtText) : "")
                                    }
                                }
                                onDoubleClicked: {
                                    if (preview.selectedFileUrl !== "") {
                                        var item = root.currentSelectedItem()
                                        inspectViewer.openViewer(preview.selectedFileUrl, item ? item.fileName : "检测原图", item ? ("架 #" + item.rack + " ╎ 轮 #" + item.slot + " ╎ " + item.receivedAtText) : "")
                                    }
                                }
                            }
                        }

                        // 路径与状态指示
                        Label {
                            Layout.fillWidth: true
                            text: (root.searchModelEpoch >= 0 && root.currentSelectedItem()) ? ("文件路径: " + (root.currentSelectedItem().filePath || "")) : "未选择项目"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeTiny
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            // 视图 1：图片画廊模式 (全宽响应式网格平铺)
            Item {
                ImageGridView {
                    id: imageGrid
                    anchors.fill: parent
                    enableInternalPaging: false
                    model: appController ? appController.searchImagesModel : null
                    columns: Math.max(2, Math.floor(width / 260))
                    rowsPerPage: 3
                    onImageClicked: function(title, date, imageUrl) {
                        inspectViewer.openViewer(imageUrl, title, date)
                    }
                }
            }
        }

        // 底部分页控制栏（两视图无缝复用共享）
        Loader {
            id: pageBarLoader
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            source: Qt.resolvedUrl("../common/PageBar.qml")
            onLoaded: {
                if (pageBarLoader.item) {
                    pageBarLoader.item.currentPage = root.currentPage
                    pageBarLoader.item.totalPages = root.totalPages
                    pageBarLoader.item.pageSize = root.pageSize
                    pageBarLoader.item.totalCount = root.totalCount

                    pageBarLoader.item.pageRequested.connect(function(page, psize) {
                        root.currentPage = page
                        root.pageSize = psize
                        root.requestPage(false)
                    })
                    pageBarLoader.item.pageSizeSelected.connect(function(psize) {
                        root.pageSize = psize
                        root.requestPage(true)
                    })
                }
            }
        }
    }

    ZoomOverlay {
        id: inspectViewer
        anchors.fill: parent
    }

    Connections {
        target: appController
        function onSearchPagedResult(total) {
            root.totalCount = total
            root.totalPages = Math.max(1, Math.ceil(total / root.pageSize))
            root.searchModelEpoch++
            if (root.shouldSelectFirst && root.viewMode === 0) {
                list.currentIndex = 0
                root.shouldSelectFirst = false
            }
            if (pageBarLoader.item) {
                pageBarLoader.item.totalCount = total
                pageBarLoader.item.totalPages = root.totalPages
                pageBarLoader.item.currentPage = root.currentPage
            }
        }
    }

    Component.onCompleted: {
        root.requestPage(true)
    }
}
