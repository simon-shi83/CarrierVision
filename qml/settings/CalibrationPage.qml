import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Item {
    id: root
    anchors.fill: parent
    Layout.fillWidth: true
    Layout.fillHeight: true

    property int selectedRack: 1
    property int currentPage: 1
    property int totalPages: 1
    property var wheelImages: [{}, {}, {}, {}, {}, {}, {}, {}]
    property var normDistanceValues: ["0", "0", "0", "0", "0", "0", "0", "0"]
    property var databaseDistanceValues: ["0", "0", "0", "0", "0", "0", "0", "0"]
    property string statusText: "请选择架号后查看轮 1 至轮 8 的最新 OK 间距图片"
    property string previewImageUrl: ""

    function loadRackImages() {
        if (!appController || !appController.loadLatestRackWheelImages) {
            statusText = "无法连接数据服务"
            return
        }

        statusText = "正在读取架号 #" + selectedRack + " 的图片..."
        if (appController && appController.latestRackWheelTotalPages) {
            root.totalPages = appController.latestRackWheelTotalPages(selectedRack) || 1
            if (root.currentPage > root.totalPages) root.currentPage = root.totalPages
        }
        if (appController && appController.loadLatestRackWheelImagesPage) {
            appController.loadLatestRackWheelImagesPage(selectedRack, root.currentPage)
        } else if (appController && appController.loadLatestRackWheelImages) {
            appController.loadLatestRackWheelImages(selectedRack)
        }
        delayedRebuildTimer.restart()
    }

    function loadRackWheelNorms() {
        if (appController && appController.rackWheelDistances)
            normDistanceValues = appController.rackWheelDistances(selectedRack)
    }

    function rebuildWheelImages() {
        if (!appController || !appController.searchImagesModel)
            return

        var selectedImages = [{}, {}, {}, {}, {}, {}, {}, {}]
        var imageModel = appController.searchImagesModel
        for (var row = 0; row < imageModel.count; ++row) {
            var image = imageModel.get(row)
            var wheelIndex = Number(image.slot) - 1
            if (wheelIndex >= 0 && wheelIndex < 8)
                selectedImages[wheelIndex] = image
        }

        var foundCount = 0
        for (var wheel = 0; wheel < 8; ++wheel) {
            if (selectedImages[wheel].fileName) {
                ++foundCount
            }
        }
        var recordDistances = ["0", "0", "0", "0", "0", "0", "0", "0"]
        for (var distanceWheel = 0; distanceWheel < 8; ++distanceWheel) {
            if (selectedImages[distanceWheel].distance !== undefined)
                recordDistances[distanceWheel] = String(selectedImages[distanceWheel].distance)
        }

        wheelImages = selectedImages
        databaseDistanceValues = recordDistances
        if (appController.searchSummary && appController.searchSummary.indexOf("失败") >= 0)
            statusText = appController.searchSummary
        else
            statusText = "架号 #" + selectedRack + "：已取得 " + foundCount + " / 8 轮有效图片"
    }

    function applyDistanceSettings() {
        if (appController && appController.saveRackWheelDistances
                && appController.saveRackWheelDistances(selectedRack, normDistanceValues)) {
            statusText = "架号 #" + selectedRack + " 的标准基准间距已成功保存"
        } else {
            statusText = "架号 #" + selectedRack + " 的标准间距保存失败"
        }
    }

    function copyMeasuredDistanceToNorm(wheelIndex) {
        const measuredDistance = Number(databaseDistanceValues[wheelIndex])
        if (measuredDistance <= 0)
            return

        var values = normDistanceValues.slice()
        values[wheelIndex] = String(databaseDistanceValues[wheelIndex])
        normDistanceValues = values
        statusText = "已将轮 " + (wheelIndex + 1) + " 的实测间距标定为标准间距"
    }

    Component.onCompleted: {
        if (appController && appController.latestRackWheelImageRack) {
            const latestRack = appController.latestRackWheelImageRack()
            if (latestRack > 0)
                selectedRack = latestRack
        }
        rackSelector.setValue(selectedRack)
        loadRackWheelNorms()
        if (appController && appController.latestRackWheelTotalPages) {
            root.totalPages = appController.latestRackWheelTotalPages(root.selectedRack) || 1
        }
        loadRackImages()
    }

    Timer {
        id: delayedRebuildTimer
        interval: 120
        repeat: false
        onTriggered: {
            rebuildWheelImages()
            if (appController && appController.searchSummary)
                statusText = appController.searchSummary
        }
    }

    Connections {
        target: appController
        function onSearchSummaryChanged() {
            root.rebuildWheelImages()
        }
        function onLatestRackLoadFinished(count, dbPath) {
            root.rebuildWheelImages()
            statusText = "取得 " + count + " 条记录 (DB: " + dbPath + ")"
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.bgCard
        border.width: 1
        border.color: Theme.borderMedium

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // 1. 顶部控制栏
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: Theme.bgCardElevated
                radius: Theme.radiusMd
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle { width: 3; height: 16; radius: 1.5; color: Theme.primary }

                    Label {
                        text: "架轮基准间距标定"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: Theme.fontSizeH3
                    }

                    Label {
                        text: "架号"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    NumPicker {
                        id: rackSelector
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 32
                        showAllButton: false
                        selectedValue: root.selectedRack
                        onValueChanged: function(value) {
                            if (value < 1 || value > 50) {
                                rackSelector.setValue(root.selectedRack)
                                return
                            }
                            if (value === root.selectedRack)
                                return
                            root.selectedRack = value
                            root.currentPage = 1
                            root.loadRackWheelNorms()
                            root.loadRackImages()
                        }
                    }

                    // 批次分页按钮组
                    RowLayout {
                        spacing: 4

                        ActionButton {
                            text: "首页"
                            variant: "secondary"
                            enabled: root.currentPage > 1
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 54
                            onClicked: {
                                root.currentPage = 1
                                if (appController && appController.latestRackWheelTotalPages)
                                    root.totalPages = appController.latestRackWheelTotalPages(root.selectedRack) || 1
                                root.loadRackImages()
                            }
                        }

                        ActionButton {
                            text: "上一页"
                            variant: "secondary"
                            enabled: root.currentPage > 1
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 64
                            onClicked: {
                                if (root.currentPage > 1) root.currentPage = Math.max(1, root.currentPage - 1)
                                if (appController && appController.latestRackWheelTotalPages)
                                    root.totalPages = appController.latestRackWheelTotalPages(root.selectedRack) || 1
                                root.loadRackImages()
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 30
                            implicitWidth: pageBadge.implicitWidth + 16
                            radius: Theme.radiusPill
                            color: Theme.bgCardActive
                            border.color: Theme.borderMedium
                            border.width: 1

                            Text {
                                id: pageBadge
                                anchors.centerIn: parent
                                text: root.currentPage + " / " + Math.max(1, root.totalPages)
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                        }

                        ActionButton {
                            text: "下一页"
                            variant: "secondary"
                            enabled: root.currentPage < Math.max(1, root.totalPages)
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 64
                            onClicked: {
                                root.currentPage = root.currentPage + 1
                                if (appController && appController.latestRackWheelTotalPages)
                                    root.totalPages = appController.latestRackWheelTotalPages(root.selectedRack) || 1
                                root.loadRackImages()
                            }
                        }

                        ActionButton {
                            text: "末页"
                            variant: "secondary"
                            enabled: root.currentPage < Math.max(1, root.totalPages)
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 54
                            onClicked: {
                                if (root.totalPages > 0) root.currentPage = Math.max(1, root.totalPages)
                                root.loadRackImages()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: root.statusText
                        color: Theme.primaryLight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                        Layout.maximumWidth: 320
                    }
                }
            }

            // 2. 8 轮基准与实测标定网格
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                color: Theme.bgInput
                radius: Theme.radiusMd
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 9
                        columnSpacing: 6
                        rowSpacing: 4

                        // Row 0: Header
                        Label { text: "参数 / 轮位"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                        Repeater {
                            model: 8
                            Label { text: "轮 " + (index + 1); horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; color: Theme.driveWheel; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                        }

                        // Row 1: Standard norm input
                        Label { text: "标准基准"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter; color: Theme.primaryLight; font.bold: true; font.pixelSize: Theme.fontSizeSmall }
                        Repeater {
                            model: 8
                            delegate: TextField {
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                text: root.normDistanceValues[index]
                                horizontalAlignment: TextInput.AlignHCenter
                                color: Theme.textPrimary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                selectByMouse: true
                                background: Rectangle {
                                    radius: Theme.radiusSm
                                    color: Theme.bgCardElevated
                                    border.width: 1
                                    border.color: parent.activeFocus ? Theme.borderHighlight : Theme.borderMedium
                                }
                                onEditingFinished: {
                                    var values = root.normDistanceValues.slice()
                                    values[index] = text === "" ? "0" : text
                                    root.normDistanceValues = values
                                }
                            }
                        }

                        // Row 2: Database measured distance
                        Label { text: "当前实测"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
                        Repeater {
                            model: 8
                            delegate: Rectangle {
                                id: measuredBox
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: Theme.radiusSm
                                color: measuredMouse.containsMouse ? Theme.bgCardActive : Theme.bgCard
                                border.width: 1
                                border.color: measuredMouse.containsMouse ? Theme.primary : Theme.borderSubtle

                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.databaseDistanceValues[measuredBox.index]
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Theme.textSecondary
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        radius: 9
                                        color: measuredMouse.containsMouse ? Theme.primaryGlow : "transparent"
                                        visible: Number(root.databaseDistanceValues[measuredBox.index]) > 0

                                        AppIcon {
                                            anchors.centerIn: parent
                                            name: "icon_arrow_down"
                                            size: 11
                                            color: measuredMouse.containsMouse ? Theme.primaryLight : Theme.textMuted
                                        }
                                    }
                                }

                                MouseArea {
                                    id: measuredMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyMeasuredDistanceToNorm(measuredBox.index)
                                    onDoubleClicked: root.copyMeasuredDistanceToNorm(measuredBox.index)
                                }

                                ToolTip.visible: measuredMouse.containsMouse
                                ToolTip.text: "轻触将实测间距标定为标准间距"
                            }
                        }
                    }

                    // 保存标定按钮
                    ActionButton {
                        text: "保存标定"
                        variant: "primary"
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: root.applyDistanceSettings()
                    }
                }
            }

            // 3. 8 轮检测原图画廊
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 4
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: 8

                    delegate: Rectangle {
                        required property int index
                        property var imageData: root.wheelImages[index] || ({})
                        property string imageUrl: imageData.fileUrl || ""
                        property string imageName: imageData.fileName || ""

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
                        radius: Theme.radiusMd
                        color: Theme.bgInput
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle { width: 3; height: 12; radius: 1.5; color: Theme.driveWheel }
                                Label {
                                    text: "轮位 #" + (index + 1)
                                    color: Theme.driveWheel
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: imageData.receivedAtText || ""
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontSizeTiny
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Theme.bgInput
                                radius: Theme.radiusSm
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: imageUrl
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    smooth: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: imageUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (imageUrl !== "") {
                                            var title = imageData.serial && imageData.serial.length > 0 ? imageData.serial : imageName
                                            var subtitle = "架 #" + root.selectedRack + " ╎ 轮 #" + (index + 1) + " ╎ " + (imageData.receivedAtText || "")
                                            viewer.openViewer(imageUrl, title, subtitle)
                                        }
                                    }
                                    onDoubleClicked: {
                                        if (imageUrl !== "") {
                                            var title = imageData.serial && imageData.serial.length > 0 ? imageData.serial : imageName
                                            var subtitle = "架 #" + root.selectedRack + " ╎ 轮 #" + (index + 1) + " ╎ " + (imageData.receivedAtText || "")
                                            viewer.openViewer(imageUrl, title, subtitle)
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    visible: imageUrl === ""
                                    spacing: 4
                                    AppIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        name: "icon_camera"
                                        size: 26
                                        color: Theme.textMuted
                                        opacity: 0.3
                                    }
                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "暂无有效图像"
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeTiny
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: imageName === "" ? "未找到该轮图片记录" : imageName
                                color: imageName === "" ? Theme.textMuted : Theme.textSecondary
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontSizeTiny
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }
        }
    }

    ZoomOverlay {
        id: viewer
        anchors.fill: parent
        visible: false
    }
}
