import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/qt/qml/CarrierVision/qml"

Item {
    id: root
    anchors.fill: parent

    // =========================================================================
    // 外部配置属性 (与原先 DesignShow 完全一致，100% 保持对外 API 兼容)
    // =========================================================================
    property bool showHeader: true
    property bool showCameraLabels: true
    property bool showDriveWheelLabels: true
    property bool showWalkWheelLabels: true
    property string descriptionText: appController ? appController.homepageDescription : ""
    property int sceneStyle: Theme.isDark ? 0 : 1 // 0: 极夜黑, 1: 工业白
    property string selectedTag: ""

    // 内部挂载容器：用于无缝承载全局单例缓存中的 3D 核心视窗
    Item {
        id: viewContainer
        anchors.fill: parent
    }

    // 尝试向全局缓存池申请挂载 3D 核心视图
    function requestAttach() {
        if (root.visible && root.width > 0 && root.height > 0) {
            DesignShowCache.claim(root, viewContainer)
        }
    }

    // 释放对 3D 核心视图的挂载
    function requestDetach() {
        DesignShowCache.release(root)
    }

    // 响应可见性与尺寸变化
    onVisibleChanged: {
        if (visible) {
            requestAttach()
        } else {
            requestDetach()
        }
    }

    onWidthChanged: {
        if (visible) {
            requestAttach()
            if (DesignShowCache.activeClient === root && DesignShowCache.sharedCore && DesignShowCache.sharedCore.updateTagPositions) {
                Qt.callLater(DesignShowCache.sharedCore.updateTagPositions)
            }
        }
    }
    onHeightChanged: {
        if (visible) {
            requestAttach()
            if (DesignShowCache.activeClient === root && DesignShowCache.sharedCore && DesignShowCache.sharedCore.updateTagPositions) {
                Qt.callLater(DesignShowCache.sharedCore.updateTagPositions)
            }
        }
    }

    // 属性动态联动
    onShowHeaderChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onShowCameraLabelsChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onShowDriveWheelLabelsChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onShowWalkWheelLabelsChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onDescriptionTextChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onSceneStyleChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)
    onSelectedTagChanged: if (DesignShowCache.activeClient === root) DesignShowCache.syncProperties(root, DesignShowCache.sharedCore)

    Component.onCompleted: {
        Qt.callLater(requestAttach)
    }

    Component.onDestruction: {
        requestDetach()
    }
}
