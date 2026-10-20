import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// 通用口令确认弹窗：输入口令后调用 verify(password)，返回 true 时关闭并发出 confirmed()，
// 否则显示 failureText。外观与退出确认弹窗一致。
Dialog {
    id: dialog
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 420
    padding: 0
    modal: true
    closePolicy: Popup.CloseOnEscape

    property string titleText: ""
    property string subtitleText: ""
    property string iconName: "icon_lock"
    property color accentColor: Theme.ng
    property color accentBgColor: Theme.ngBg
    property color subtitleColor: Theme.textMuted
    property color focusBorderColor: accentColor
    property int confirmWidth: 90
    property string placeholderText: "请输入口令"
    property string confirmText: "确认"
    property string confirmVariant: "danger"
    property string failureText: "口令错误，请重新输入"
    // 由使用方提供：function(password) -> bool
    property var verify: null
    property string errorMessage: ""

    signal confirmed()

    background: Rectangle {
        radius: Theme.radiusLg
        color: Theme.bgPopup
        border.width: 1
        border.color: Theme.borderMedium
    }

    header: Rectangle {
        implicitHeight: 68
        color: Theme.bgCardElevated
        radius: Theme.radiusLg

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 12
            color: parent.color
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 16
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: dialog.accentBgColor
                border.color: dialog.accentColor
                border.width: 1

                AppIcon {
                    anchors.centerIn: parent
                    name: dialog.iconName
                    size: 18
                    color: dialog.accentColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: dialog.titleText
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }

                Label {
                    Layout.fillWidth: true
                    text: dialog.subtitleText
                    color: dialog.subtitleColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Button {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                text: "✕"
                onClicked: dialog.close()
                contentItem: Text {
                    text: parent.text
                    color: Theme.textMuted
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 14
                    color: parent.hovered ? Theme.bgCardActive : "transparent"
                }
            }
        }
    }

    onOpened: {
        passwordInput.text = "";
        errorMessage = "";
        passwordInput.forceActiveFocus();
        Qt.callLater(function () {
            if (appController)
                appController.activateEnglishInputMethod();
        });
    }

    // 不使用 Dialog.accept()：它在发出 accepted 后总会关闭弹窗，验证失败时错误提示无法显示
    function submit() {
        if (typeof verify === "function" && verify(passwordInput.text)) {
            passwordInput.text = "";
            close();
            confirmed();
            return;
        }
        errorMessage = failureText;
        passwordInput.selectAll();
        passwordInput.forceActiveFocus();
    }

    contentItem: Item {
        implicitHeight: content.implicitHeight + 24

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 16
            anchors.bottomMargin: 8
            spacing: 10

            TextField {
                id: passwordInput
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhLatinOnly | Qt.ImhNoPredictiveText
                placeholderText: dialog.placeholderText
                placeholderTextColor: Theme.textMuted
                color: Theme.textPrimary
                font.family: Theme.fontMono
                selectByMouse: true
                onActiveFocusChanged: {
                    if (activeFocus && appController)
                        appController.activateEnglishInputMethod();
                }
                onAccepted: dialog.submit()

                background: Rectangle {
                    radius: Theme.radiusMd
                    color: Theme.bgInput
                    border.width: 1
                    border.color: passwordInput.activeFocus ? dialog.focusBorderColor : Theme.borderMedium
                }
            }

            Label {
                Layout.fillWidth: true
                visible: dialog.errorMessage !== ""
                text: dialog.errorMessage
                color: Theme.ngLight
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    footer: Rectangle {
        implicitHeight: 58
        color: Theme.bgCardElevated
        radius: Theme.radiusLg

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 12
            color: parent.color
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 10

            Item {
                Layout.fillWidth: true
            }

            ActionButton {
                text: "取消"
                variant: "secondary"
                Layout.preferredWidth: 76
                Layout.preferredHeight: 34
                onClicked: dialog.close()
            }

            ActionButton {
                text: dialog.confirmText
                variant: dialog.confirmVariant
                Layout.preferredWidth: dialog.confirmWidth
                Layout.preferredHeight: 34
                onClicked: dialog.submit()
            }
        }
    }
}
