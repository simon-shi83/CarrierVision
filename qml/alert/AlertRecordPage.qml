import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../common"

Page {
    id: root
    property bool alertMode: true
    property int pendingTotalCount: -1
    property var queryHover: null
    anchors.fill: parent
    background: Rectangle {
        color: "transparent"
    }

    // 分页相关属性
    property int currentPage: 1
    property int pageSize: 10
    property int totalPages: 1
    property int totalCount: 0
    property bool shouldSelectFirst: false

    function updatePaging(total) {
        totalCount = total
        totalPages = Math.max(1, Math.ceil(totalCount / pageSize))
        if (currentPage > totalPages)
            currentPage = totalPages
    }

    function requestPage(resetToFirst) {
        if (resetToFirst)
            currentPage = 1
        var start = queryCond.startDate || ""
        var end = queryCond.endDate || ""
        var rack = queryCond.rackno || 0
        var wheel = (queryCond.turno === undefined || queryCond.turno === "全部") ? "" : queryCond.turno
        var resFlag = (queryCond.result === "OK") ? "1" : (queryCond.result === "NG" ? "0" : "")

        if (alertMode && appController && appController.alertSearchPaged) {
            root.shouldSelectFirst = true
            appController.alertSearchPaged(start, end, rack, wheel, currentPage, pageSize)
            if (pageBarLoader.item) {
                pageBarLoader.item.currentPage = currentPage
                pageBarLoader.item.pageSize = pageSize
            }
        } else if (appController && appController.searchPaged) {
            root.shouldSelectFirst = true
            appController.searchPaged(start, end, queryCond.keyword || "", rack, wheel, resFlag, currentPage, pageSize)
            if (pageBarLoader.item) {
                pageBarLoader.item.currentPage = currentPage
                pageBarLoader.item.pageSize = pageSize
            }
        }
    }

    function openGenericQuery(startDate, endDate, wheelNumber, resultType) {
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

        // 顶部：高精组合查询栏
        QueryConditionBar {
            id: queryCond
            Layout.fillWidth: true
            includeResult: !root.alertMode
            onSearchClicked: {
                requestPage(true)
            }
            onResetClicked: {
                if (root.alertMode)
                    root.requestPage(true)
                else
                    appController.clearSearch()
            }
        }

        // 下方：左列表 + 右预览
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // 左侧：数据列表卡片
            Rectangle {
                Layout.preferredWidth: root.width * 0.58
                Layout.fillHeight: true
                radius: Theme.radiusLg
                color: Theme.bgCard
                border.width: 1
                border.color: Theme.borderMedium

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // 分页控制栏
                    Loader {
                        id: pageBarLoader
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        source: Qt.resolvedUrl("../common/PageBar.qml")
                        onLoaded: {
                            if (pageBarLoader.item) {
                                pageBarLoader.item.currentPage = currentPage
                                pageBarLoader.item.totalPages = totalPages
                                pageBarLoader.item.pageSize = pageSize
                                pageBarLoader.item.totalCount = totalCount
                                if (root.pendingTotalCount >= 0) {
                                    pageBarLoader.item.totalCount = root.pendingTotalCount
                                    pageBarLoader.item.totalPages = Math.max(1, Math.ceil(root.pendingTotalCount / pageBarLoader.item.pageSize))
                                    root.pendingTotalCount = -1
                                }
                                pageBarLoader.item.pageRequested.connect(function (page, psize) {
                                    currentPage = page
                                    pageSize = psize
                                    requestPage(false)
                                })
                                pageBarLoader.item.pageSizeSelected.connect(function (psize) {
                                    pageSize = psize
                                    requestPage(true)
                                })
                            }
                        }
                    }

                    // 表格固定表头
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        color: Theme.bgCardElevated
                        radius: Theme.radiusMd
                        border.color: Theme.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            Text {
                                text: "时间 / 文件名"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "架号"
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                            Text {
                                text: "轮号"
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                            Text {
                                text: "距离(小)"
                                Layout.preferredWidth: 54
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                            Text {
                                text: "距离(大)"
                                Layout.preferredWidth: 54
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                            Text {
                                text: "基准"
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                            Text {
                                text: "判定"
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignHCenter
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
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

                        delegate: Rectangle {
                            id: itemRect
                            height: 64
                            width: list.width
                            radius: Theme.radiusMd
                            property bool selected: index === list.currentIndex
                            property bool hovered: mouseArea.containsMouse

                            color: selected ? Theme.bgCardActive : (hovered ? Theme.bgCardElevated : ((index % 2 === 0) ? Theme.bgInput : "transparent"))

                            border.width: 1
                            border.color: selected ? Theme.primary : (hovered ? Theme.borderMedium : "transparent")

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
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 8

                                // 左侧时间与文件名
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: receivedAtText
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                        color: selected ? Theme.primaryLight : Theme.textPrimary
                                    }
                                    Text {
                                        text: fileName
                                        elide: Text.ElideMiddle
                                        color: Theme.textSecondary
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeTiny
                                    }
                                }

                                Text {
                                    text: String(rack)
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeBody
                                }
                                Text {
                                    text: String(slot)
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textPrimary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeBody
                                }
                                Text {
                                    text: String(distance)
                                    Layout.preferredWidth: 54
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textSecondary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Text {
                                    text: String(dist_max)
                                    Layout.preferredWidth: 54
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textSecondary
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Text {
                                    text: String(dist_norm)
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeSmall
                                }

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
                            if (count > 0)
                                Qt.callLater(function () {
                                    list.currentIndex = 0
                                })
                            else
                                list.currentIndex = -1
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
                        Rectangle {
                            width: 3
                            height: 14
                            radius: 1.5
                            color: Theme.primary
                        }
                        Label {
                            text: "点检原图精准检验视窗"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeH3
                            font.bold: true
                        }
                        Item {
                            Layout.fillWidth: true
                        }
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
    }

    ZoomOverlay {
        id: inspectViewer
        anchors.fill: parent
    }

    property int searchModelEpoch: 0

    Connections {
        target: appController
        function onSearchPagedResult(total) {
            root.totalCount = total
            root.totalPages = Math.max(1, Math.ceil(total / root.pageSize))
            root.searchModelEpoch++
            if (root.shouldSelectFirst) {
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
        requestPage(true)
    }
}
