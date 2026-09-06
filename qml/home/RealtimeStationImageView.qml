import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".."
import "../common"

Rectangle {
    id: root
    anchors.fill: parent

    Layout.fillWidth: true
    Layout.fillHeight: true

    property var imageModel: (typeof appController !== 'undefined' && appController) ? appController.currentImagesModel : null
    property string titleText: "实时工位图像监控"
    property string summaryText: (appController && appController.lastTcpMessage && appController.lastTcpMessage.length > 0)
                                     ? ("TCP 消息: " + appController.lastTcpMessage)
                                     : ((appController && appController.currentSerialsRaw.length > 0)
                                         ? ("当前序列号: " + appController.currentSerialsRaw)
                                         : "等待新的 TCP 点检信号...")
    property string emptyText: "等待新的批次图像到达"

    property int refreshEpoch: 0

    Connections {
        target: typeof appController !== 'undefined' ? appController : null
        function onSlotUpdated(slot) {
            root.refreshEpoch++
        }
        function onCurrentBatchChanged() {
            root.refreshEpoch++
        }
    }

    Connections {
        target: root.imageModel && root.imageModel.dataChanged ? root.imageModel : null
        ignoreUnknownSignals: true
        function onDataChanged() {
            root.refreshEpoch++
        }
        function onModelReset() {
            root.refreshEpoch++
        }
    }

    property bool embeddedMode: false
    property var externalViewer: null

    radius: embeddedMode ? 0 : Theme.radiusLg
    color: embeddedMode ? "transparent" : Theme.bgCard
    border.width: embeddedMode ? 0 : 1
    border.color: embeddedMode ? "transparent" : Theme.borderMedium

    ZoomOverlay {
        id: viewer
        anchors.fill: parent
        visible: !root.embeddedMode && viewerSource !== ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.embeddedMode ? 0 : 12
        spacing: root.embeddedMode ? 0 : 8

        // 顶栏汇总指示
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.embeddedMode

            Rectangle {
                width: 4
                height: 18
                radius: 2
                color: Theme.primary
            }

            Label {
                text: root.titleText
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeH2
                font.bold: true
            }

            Rectangle {
                Layout.preferredHeight: 22
                implicitWidth: tcpMsgText.implicitWidth + 16
                radius: Theme.radiusPill
                color: Theme.bgCardElevated
                border.color: Theme.borderSubtle
                border.width: 1
                visible: root.summaryText.length > 0

                Text {
                    id: tcpMsgText
                    anchors.centerIn: parent
                    text: root.summaryText
                    color: Theme.primaryLight
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredHeight: 22
                implicitWidth: hintRow.implicitWidth + 14
                radius: Theme.radiusPill
                color: Theme.bgCardElevated
                border.color: Theme.borderSubtle
                border.width: 1

                RowLayout {
                    id: hintRow
                    anchors.centerIn: parent
                    spacing: 4

                    AppIcon {
                        name: "icon_eye"
                        size: 11
                        color: Theme.textMuted
                    }

                    Text {
                        text: "轻触或双击卡片进入全景缩放"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeTiny
                    }
                }
            }
        }

        // 8/12 相机网格容器
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMd
            color: Theme.bgInput
            border.width: 1
            border.color: Theme.borderSubtle

            GridLayout {
                id: gridLayout
                anchors.fill: parent
                anchors.margins: 8
                columns: 4
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: (root.imageModel && root.imageModel.count > 0) ? root.imageModel.count : 12
                    ImageCard {
                        property var itemObject: (root.refreshEpoch >= 0 && root.imageModel && index < root.imageModel.count) ? root.imageModel.itemObjectAt(index) : null
                        slotIndex: index
                        fileUrl: itemObject ? itemObject.fileUrl : ""
                        filePath: itemObject ? itemObject.filePath : ""
                        fileName: itemObject ? itemObject.fileName : ""
                        serial: itemObject ? itemObject.serial : ""
                        roundNumber: itemObject ? itemObject.roundNumber : 0
                        receivedAtText: itemObject ? itemObject.receivedAtText : ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onActivate: function(sourceUrl, title, subtitle) {
                            if (root.externalViewer) {
                                root.externalViewer.openViewer(sourceUrl, title, subtitle)
                            } else {
                                viewer.openViewer(sourceUrl, title, subtitle)
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // 批次图像卡片私有内联组件
    // ==========================================
    component ImageCard: Rectangle {
        id: cardRoot

        property url fileUrl
        property string filePath: ""
        property string fileName: ""
        property string serial: ""
        property int roundNumber: 0
        property string receivedAtText: ""
        property int slotIndex: 0

        function effectiveImageSource() {
            var u = String(cardRoot.fileUrl || "")
            if (u.length > 0) { return u }
            var p = String(cardRoot.filePath || "")
            if (p.length === 0) { return "" }
            var normalized = p.replace(/\\/g, "/")
            if (/^[a-zA-Z]:\//.test(normalized)) { return "file:///" + normalized }
            return normalized
        }

        signal activate(url sourceUrl, string titleText, string subtitleText)

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
                    color: cardRoot.effectiveImageSource() !== "" ? Theme.primaryGlow : Theme.bgCardElevated
                    border.color: cardRoot.effectiveImageSource() !== "" ? Theme.primary : Theme.borderSubtle
                    border.width: 1

                    Text {
                        id: camText
                        anchors.centerIn: parent
                        text: "CAM " + (cardRoot.slotIndex < 9 ? "0" : "") + (cardRoot.slotIndex + 1)
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        font.bold: true
                        color: cardRoot.effectiveImageSource() !== "" ? Theme.primaryLight : Theme.textMuted
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

            // 图像预览容器
            Rectangle {
                id: previewFrame
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusSm
                color: Theme.bgInput
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                Image {
                    id: previewImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: cardRoot.effectiveImageSource()
                    sourceSize.width: Math.min(4096, Math.max(1, width * 2))
                    sourceSize.height: Math.min(4096, Math.max(1, height * 2))
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                // 无图像占位符
                Rectangle {
                    id: placeholderBox
                    anchors.fill: parent
                    color: "transparent"
                    visible: cardRoot.effectiveImageSource() === ""

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
                    visible: mouseArea.containsMouse && cardRoot.effectiveImageSource() !== ""
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
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: cardRoot.effectiveImageSource() !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (cardRoot.effectiveImageSource() !== "") {
                    const title = cardRoot.serial.length > 0 ? cardRoot.serial : cardRoot.fileName
                    const subtitle = "工位相机 #" + (cardRoot.slotIndex + 1) + " ╎ " + cardRoot.receivedAtText
                    cardRoot.activate(cardRoot.effectiveImageSource(), title, subtitle)
                }
            }
            onDoubleClicked: {
                if (cardRoot.effectiveImageSource() !== "") {
                    const title = cardRoot.serial.length > 0 ? cardRoot.serial : cardRoot.fileName
                    const subtitle = "工位相机 #" + (cardRoot.slotIndex + 1) + " ╎ " + cardRoot.receivedAtText
                    cardRoot.activate(cardRoot.effectiveImageSource(), title, subtitle)
                }
            }
        }
    }
}
