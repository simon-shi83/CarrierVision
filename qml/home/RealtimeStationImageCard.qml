import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Rectangle {
    id: cardRoot

    property int slotIndex: 0
    property var imageModel: null
    property var itemObject: null

    function syncFromModel() {
        var model = imageModel || ((typeof root !== 'undefined' && root && root.imageModel) ? root.imageModel : null)
        if (!model && typeof appController !== 'undefined' && appController) {
            model = appController.currentImagesModel
        }
        if (model && slotIndex < model.count) {
            var obj = model.itemObjectAt(slotIndex)
            if (itemObject !== obj) {
                itemObject = obj
            }
        } else {
            itemObject = null
        }
        var src = effectiveImageSource()
        if (src !== previewFrame.activeDisplayedSource) {
            previewFrame.updateSource(src)
        }
    }

    property url fileUrl: (itemObject && itemObject.fileUrl) ? itemObject.fileUrl : ""
    property string filePath: (itemObject && itemObject.filePath) ? itemObject.filePath : ""
    property string fileName: (itemObject && itemObject.fileName) ? itemObject.fileName : ""
    property string serial: (itemObject && itemObject.serial) ? itemObject.serial : ""
    property int roundNumber: (itemObject && itemObject.roundNumber) ? itemObject.roundNumber : 0
    property string receivedAtText: (itemObject && itemObject.receivedAtText) ? itemObject.receivedAtText : ""
    property string wheelsInfo: (itemObject && itemObject.wheelsInfo) ? itemObject.wheelsInfo : ""
    property int result: (itemObject && itemObject.result !== undefined) ? itemObject.result : 1

    function effectiveImageSource() {
        var u = String(cardRoot.fileUrl || "")
        if (u.length > 0) { return u }
        var p = String(cardRoot.filePath || "")
        if (p.length === 0) { return "" }
        var normalized = p.replace(/\\/g, "/")
        if (/^[a-zA-Z]:\//.test(normalized)) { return "file:///" + normalized }
        if (normalized.startsWith("/")) { return "file://" + normalized }
        return normalized
    }

    readonly property string currentTargetSource: effectiveImageSource()
    readonly property bool hasImage: currentTargetSource.length > 0

    onCurrentTargetSourceChanged: {
        previewFrame.updateSource(currentTargetSource)
    }

    Component.onCompleted: {
        syncFromModel()
        if (currentTargetSource.length > 0) {
            previewFrame.updateSource(currentTargetSource)
        }
    }

    signal activate(url sourceUrl, string titleText, string subtitleText, int slotIndex)

    radius: Theme.radiusMd
    color: mouseArea.containsMouse ? Theme.bgCardActive : Theme.bgCard
    border.width: 1
    border.color: mouseArea.containsMouse ? Theme.borderHover : Theme.borderMedium
    clip: true

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // 顶部信息与相机工位徽章
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4

            Rectangle {
                Layout.preferredHeight: 20
                implicitWidth: camText.implicitWidth + 12
                radius: Theme.radiusPill
                color: !cardRoot.hasImage ? Theme.bgCardElevated : (cardRoot.result === 0 ? Theme.ngGlow : Theme.primaryGlow)
                border.color: !cardRoot.hasImage ? Theme.borderSubtle : (cardRoot.result === 0 ? Theme.ng : Theme.primary)
                border.width: 1

                Text {
                    id: camText
                    anchors.centerIn: parent
                    text: "CAM " + (cardRoot.slotIndex < 9 ? "0" : "") + (cardRoot.slotIndex + 1) + (cardRoot.hasImage && cardRoot.result === 0 ? " [NG]" : "")
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.bold: true
                    color: !cardRoot.hasImage ? Theme.textMuted : (cardRoot.result === 0 ? Theme.ngLight : Theme.primaryLight)
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: cardRoot.receivedAtText
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 10
                elide: Label.ElideRight
            }
        }

        // 图像预览容器 (双缓冲渲染结构，消除重载闪屏)
        Rectangle {
            id: previewFrame
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusSm
            color: Theme.bgInput
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

            property bool showingA: true
            property string displayedSourceA: ""
            property string displayedSourceB: ""
            readonly property string activeDisplayedSource: showingA ? displayedSourceA : displayedSourceB

            function updateSource(newSrc) {
                if (newSrc === activeDisplayedSource) {
                    return
                }
                if (!newSrc || newSrc.length === 0) {
                    displayedSourceA = ""
                    displayedSourceB = ""
                    imageA.source = ""
                    imageB.source = ""
                    showingA = true
                    return
                }
                // 初次加载（此前没有显示任何图像）：直接赋给 A，平滑淡入
                if (activeDisplayedSource.length === 0) {
                    showingA = true
                    displayedSourceA = newSrc
                    imageA.source = newSrc
                    return
                }
                // 已有显示图像：双缓冲后台静默解码，保持当前画面完全可见，绝不黑屏/闪烁
                if (showingA) {
                    displayedSourceB = newSrc
                    imageB.source = newSrc
                } else {
                    displayedSourceA = newSrc
                    imageA.source = newSrc
                }
            }

            // 双缓冲 A
            Image {
                id: imageA
                anchors.fill: parent
                anchors.margins: 2
                sourceSize: Qt.size(1280, 1280)
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: (previewFrame.showingA && status === Image.Ready) ? 1.0 : 0.0
                visible: opacity > 0.0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast }
                }

                onStatusChanged: {
                    if (status === Image.Ready && !previewFrame.showingA && previewFrame.displayedSourceA !== "") {
                        previewFrame.showingA = true
                        cleanTimer.targetBuffer = "B"
                        cleanTimer.restart()
                    }
                }
            }

            // 双缓冲 B
            Image {
                id: imageB
                anchors.fill: parent
                anchors.margins: 2
                sourceSize: Qt.size(1280, 1280)
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: (!previewFrame.showingA && status === Image.Ready) ? 1.0 : 0.0
                visible: opacity > 0.0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast }
                }

                onStatusChanged: {
                    if (status === Image.Ready && previewFrame.showingA && previewFrame.displayedSourceB !== "") {
                        previewFrame.showingA = false
                        cleanTimer.targetBuffer = "A"
                        cleanTimer.restart()
                    }
                }
            }

            Timer {
                id: cleanTimer
                interval: Theme.animFast + 60
                repeat: false
                property string targetBuffer: ""
                onTriggered: {
                    if (targetBuffer === "A" && !previewFrame.showingA) {
                        imageA.source = ""
                        previewFrame.displayedSourceA = ""
                    } else if (targetBuffer === "B" && previewFrame.showingA) {
                        imageB.source = ""
                        previewFrame.displayedSourceB = ""
                    }
                }
            }

            // 无图像占位符 (支持平滑淡入淡出)
            Rectangle {
                id: placeholderBox
                anchors.fill: parent
                color: "transparent"
                visible: opacity > 0.0
                opacity: (!cardRoot.hasImage && previewFrame.activeDisplayedSource.length === 0) ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.animFast }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    AppIcon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "icon_camera"
                        size: 28
                        color: Theme.textMuted
                        opacity: 0.35
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: "等待图像传输"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // 悬停检验动作浮层 (高精 HMI 交互反馈)
            Rectangle {
                id: hoverOverlay
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                visible: mouseArea.containsMouse && cardRoot.hasImage
                radius: Theme.radiusSm

                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                Rectangle {
                    anchors.centerIn: parent
                    height: 28
                    implicitWidth: hoverRow.implicitWidth + 16
                    radius: Theme.radiusPill
                    color: Theme.bgCardElevated
                    border.color: Theme.primary
                    border.width: 1

                    RowLayout {
                        id: hoverRow
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            name: "icon_eye"
                            size: 14
                            color: Theme.primaryLight
                        }

                        Text {
                            text: "全景检验"
                            color: Theme.primaryLight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }
                }
            }
        }

        // 序列号 / 文件名标签
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: cardRoot.serial.length > 0 ? cardRoot.serial : (cardRoot.fileName.length > 0 ? cardRoot.fileName : "待采集")
            color: cardRoot.serial.length > 0 ? Theme.primaryLight : Theme.textSecondary
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            elide: Label.ElideMiddle
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            visible: cardRoot.wheelsInfo.length > 0
            text: cardRoot.wheelsInfo
            color: cardRoot.result === 0 ? Theme.ngLight : Theme.okLight
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.bold: true
            elide: Label.ElideRight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: cardRoot.hasImage ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (cardRoot.hasImage) {
                const title = cardRoot.serial.length > 0 ? cardRoot.serial : cardRoot.fileName
                const subtitle = "工位相机 #" + (cardRoot.slotIndex + 1) + " ╎ " + cardRoot.receivedAtText
                cardRoot.activate(cardRoot.currentTargetSource, title, subtitle, cardRoot.slotIndex)
            }
        }
        onDoubleClicked: {
            if (cardRoot.hasImage) {
                const title = cardRoot.serial.length > 0 ? cardRoot.serial : cardRoot.fileName
                const subtitle = "工位相机 #" + (cardRoot.slotIndex + 1) + " ╎ " + cardRoot.receivedAtText
                cardRoot.activate(cardRoot.currentTargetSource, title, subtitle, cardRoot.slotIndex)
            }
        }
    }
}
