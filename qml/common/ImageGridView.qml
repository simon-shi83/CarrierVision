import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: Theme.bgCard
    border.color: Theme.borderMedium
    border.width: 1
    radius: Theme.radiusMd

    property var model
    readonly property int count: model ? model.count : 0
    property int columns: 4
    property int rowsPerPage: 3
    property int itemsPerPage: columns * rowsPerPage
    property int currentPage: 0
    property bool enableInternalPaging: true
    readonly property int totalPages: Math.max(1, Math.ceil(count / itemsPerPage))

    property int refreshEpoch: 0

    Connections {
        target: typeof appController !== "undefined" ? appController : null
        function onSlotUpdated(slot) {
            root.refreshEpoch++
        }
        function onCurrentBatchChanged() {
            root.refreshEpoch++
        }
    }

    Connections {
        target: root.model && root.model.dataChanged ? root.model : null
        ignoreUnknownSignals: true
        function onDataChanged() {
            root.refreshEpoch++
        }
        function onModelReset() {
            root.refreshEpoch++
        }
    }

    signal imageClicked(string title, string date, string imageUrl)

    function clampPage(page) {
        if (page < 0)
            return 0
        if (page >= totalPages)
            return totalPages - 1
        return page
    }

    function showPage(page) {
        currentPage = clampPage(page)
    }

    GridLayout {
        id: imageGrid
        anchors.fill: parent
        anchors.margins: 10
        columns: root.columns
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: root.itemsPerPage

            delegate: Rectangle {
                readonly property int itemIndex: root.enableInternalPaging ? (root.currentPage * root.itemsPerPage + index) : index
                readonly property var itemData: (root.refreshEpoch >= 0 && root.model && itemIndex < root.count) ? root.model.get(itemIndex) : null

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: Math.floor((imageGrid.width - (root.columns - 1) * imageGrid.columnSpacing) / root.columns)
                Layout.preferredHeight: Math.floor((imageGrid.height - (root.rowsPerPage - 1) * imageGrid.rowSpacing) / root.rowsPerPage)
                visible: itemData !== null

                color: itemMouse.containsMouse ? Theme.bgCardActive : Theme.bgInput
                radius: Theme.radiusMd
                border.color: itemMouse.containsMouse ? Theme.primary : Theme.borderSubtle
                border.width: itemMouse.containsMouse ? 2 : 1

                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    enabled: parent.visible
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.imageClicked(itemData ? itemData.fileName : "", itemData ? itemData.receivedAtText : "", itemData ? itemData.fileUrl : "")
                    }
                    onDoubleClicked: {
                        root.imageClicked(itemData ? itemData.fileName : "", itemData ? itemData.receivedAtText : "", itemData ? itemData.fileUrl : "")
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: Theme.bgCardElevated
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: itemData ? itemData.fileUrl : ""
                            sourceSize.width: Math.min(4096, Math.max(1, width * 2))
                            sourceSize.height: Math.min(4096, Math.max(1, height * 2))
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            smooth: true

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.bgInput
                                z: -1

                                Text {
                                    anchors.centerIn: parent
                                    text: "加载中..."
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }

                        // 左上角：架号与轮位胶囊
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 5
                            height: 20
                            radius: Theme.radiusSm
                            color: Theme.isDark ? "#cc0f172a" : "#e6ffffff"
                            border.width: 1
                            border.color: Theme.borderSubtle
                            implicitWidth: rackSlotTxt.implicitWidth + 10
                            visible: itemData && itemData.rack !== undefined

                            Text {
                                id: rackSlotTxt
                                anchors.centerIn: parent
                                text: itemData ? ("架 #" + itemData.rack + " ╎ 轮 " + itemData.slot) : ""
                                color: Theme.textSecondary
                                font.family: Theme.fontMono
                                font.bold: true
                                font.pixelSize: Theme.fontSizeTiny
                            }
                        }

                        // 右上角：OK / NG 判定药丸
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 5
                            height: 20
                            radius: Theme.radiusPill
                            implicitWidth: resTxt.implicitWidth + 12
                            visible: itemData && itemData.result !== undefined
                            color: itemData && itemData.result === 1 ? Theme.okBg : Theme.ngBg
                            border.width: 1
                            border.color: itemData && itemData.result === 1 ? Theme.okBorder : Theme.ngBorder

                            Text {
                                id: resTxt
                                anchors.centerIn: parent
                                text: itemData ? (itemData.result === 1 ? "OK 正常" : "NG 异常") : ""
                                color: itemData && itemData.result === 1 ? Theme.okLight : Theme.ngLight
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: Theme.fontSizeTiny
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: itemData ? itemData.fileName : ""
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.textPrimary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: itemData ? itemData.receivedAtText : ""
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    WheelHandler {
        target: null
        enabled: root.enableInternalPaging
        onWheel: function(event) {
            if (!root.enableInternalPaging) return
            if (event.angleDelta.y < 0)
                root.showPage(root.currentPage + 1)
            else if (event.angleDelta.y > 0)
                root.showPage(root.currentPage - 1)
            event.accepted = true
        }
    }

    // 空状态提示
    Rectangle {
        anchors.centerIn: parent
        visible: root.count === 0
        color: "transparent"

        ColumnLayout {
            spacing: 6
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "📷"
                font.pixelSize: 36
                opacity: 0.4
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "暂无图像记录"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }
        }
    }

    // 分页胶囊（仅在内部独立分页模式下显示）
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        radius: Theme.radiusPill
        color: Theme.bgCardActive
        border.color: Theme.borderMedium
        border.width: 1
        visible: root.enableInternalPaging && root.count > 0
        implicitWidth: pageLabel.implicitWidth + 20
        implicitHeight: pageLabel.implicitHeight + 8

        Text {
            id: pageLabel
            anchors.centerIn: parent
            text: "第 " + String(root.currentPage + 1) + " / " + String(root.totalPages) + " 页"
            color: Theme.textPrimary
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }
    }
}
