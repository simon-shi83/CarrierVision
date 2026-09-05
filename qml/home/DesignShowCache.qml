pragma Singleton
import QtQuick 2.15

QtObject {
    id: cache

    // 当前持有 3D 核心视图的活跃宿主组件
    property var activeClient: null

    // 全局唯一常驻的 3D 数字孪生渲染核心 (持有 73MB GLB 模型与显存顶点缓冲区)
    property Item sharedCore: null

    // 静态内联组件模板 (确保编译期类型检查与高效实例化)
    property Component coreComponent: Component {
        DesignShowCore {}
    }

    // 获取或惰性初始化 3D 核心单例实例
    function getOrCreateCore() {
        if (!sharedCore) {
            sharedCore = coreComponent.createObject(null)
            if (!sharedCore) {
                console.warn("[DesignShowCache] 3D 数字孪生核心实例初始化失败")
            } else {
                sharedCore.visible = false
                sharedCore.selectedTagChanged.connect(function() {
                    if (activeClient && activeClient.selectedTag !== undefined && activeClient.selectedTag !== sharedCore.selectedTag) {
                        activeClient.selectedTag = sharedCore.selectedTag
                    }
                })
            }
        }
        return sharedCore
    }

    // 申请挂载 3D 核心视图到指定页面容器 (0ms 瞬间秒开，共享同一份 73MB 模型缓存)
    function claim(client, container) {
        if (!client || !container) return
        var core = getOrCreateCore()
        if (!core) return

        activeClient = client

        // 将全局核心挂载到当前页面容器中
        if (core.parent !== container) {
            core.anchors.fill = undefined
            core.parent = container
            core.anchors.fill = container
        }
        core.visible = true

        // 立即同步宿主配置与视口状态
        syncProperties(client, core)

        Qt.callLater(function() {
            if (core.updateTagPositions) core.updateTagPositions()
        })
        mountRefreshTimer1.restart()
        mountRefreshTimer2.restart()
    }

    // 延时保险刷新器：确保宿主组件布局完成与 3D 投影变换矩阵生效后，必定精准刷新全部标签
    property Timer mountRefreshTimer1: Timer {
        interval: 80
        repeat: false
        onTriggered: {
            if (sharedCore && sharedCore.updateTagPositions) sharedCore.updateTagPositions()
        }
    }

    property Timer mountRefreshTimer2: Timer {
        interval: 320
        repeat: false
        onTriggered: {
            if (sharedCore && sharedCore.updateTagPositions) sharedCore.updateTagPositions()
        }
    }

    // 释放挂载
    function release(client) {
        if (activeClient === client && sharedCore) {
            activeClient = null
            sharedCore.visible = false
            sharedCore.anchors.fill = undefined
            sharedCore.parent = null
        }
    }

    // 属性动态同步
    function syncProperties(client, core) {
        if (!client || !core) return
        if (client.showHeader !== undefined)
            core.showHeader = client.showHeader
        if (client.showCameraLabels !== undefined)
            core.showCameraLabels = client.showCameraLabels
        if (client.showDriveWheelLabels !== undefined)
            core.showDriveWheelLabels = client.showDriveWheelLabels
        if (client.showWalkWheelLabels !== undefined)
            core.showWalkWheelLabels = client.showWalkWheelLabels
        if (client.descriptionText !== undefined && client.descriptionText !== "")
            core.descriptionText = client.descriptionText
        if (client.sceneStyle !== undefined)
            core.sceneStyle = client.sceneStyle
        if (client.selectedTag !== undefined)
            core.selectedTag = client.selectedTag
    }
}
