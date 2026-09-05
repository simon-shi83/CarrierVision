import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick3D 6.5
import QtQuick3D.AssetUtils

Page {
    id: root
    anchors.fill: parent
    background: Rectangle { color: "transparent" }

    // 外部可配置属性
    property bool showHeader: true
    property bool showCameraLabels: true
    property bool showDriveWheelLabels: true
    property bool showWalkWheelLabels: true
    property string descriptionText: (typeof appController !== 'undefined' && appController) ? appController.homepageDescription : ""
    property int sceneStyle: Theme.isDark ? 0 : 1 // 0: 极夜黑 (Dark Mode), 1: 工业白 (Light Mode)
    property string selectedTag: "" // 当前选中的标签名称 (点击击中高亮)

    onSelectedTagChanged: {
        if (!selectedTag) return
        var targetStation = ""
        for (var i = 0; i < driveWheelList.length; ++i) {
            if (driveWheelList[i].name === selectedTag) {
                targetStation = driveWheelList[i].station; break;
            }
        }
        if (!targetStation) {
            for (var j = 0; j < walkWheelList.length; ++j) {
                if (walkWheelList[j].name === selectedTag) {
                    targetStation = walkWheelList[j].station; break;
                }
            }
        }
        if (!targetStation) {
            for (var k = 0; k < cameraList.length; ++k) {
                if (cameraList[k].name === selectedTag) {
                    targetStation = cameraList[k].station; break;
                }
            }
        }
        if (targetStation && modelContainer && modelContainer.animateToView) {
            if (modelPivot.pitch > 55) {
                // 俯视模式下保持俯视大局观视角，更新标签矩阵
                modelContainer.updateTagPositions()
            } else {
                var targetYaw = (targetStation === "左侧工位") ? 22 : 36
                modelContainer.animateToView(modelPivot.pitch > 0 ? modelPivot.pitch : 22, targetYaw, camera.z)
            }
        }
    }

    function updateTagPositions() {
        if (modelContainer && modelContainer.updateTagPositions) {
            modelContainer.updateTagPositions()
        }
    }

    onWidthChanged: if (visible && width > 0) Qt.callLater(updateTagPositions)
    onHeightChanged: if (visible && height > 0) Qt.callLater(updateTagPositions)

    onVisibleChanged: {
        if (!visible) {
            autoRotateTimer.running = false
            viewAnim.stop()
        } else {
            Qt.callLater(updateTagPositions)
        }
    }

    // 相机数据列表 (根据产线点检槽位与物理相机点检布局标定)
    readonly property var cameraList: [
        // 左侧工位
        { name: "相机1",  node: cam1_1, station: "左侧工位", desc: "侧前视点检" },
        { name: "相机2",  node: cam1_2, station: "左侧工位", desc: "侧后视点检" },
        { name: "相机10", node: cam1_3, station: "左侧工位", desc: "斜俯视点检" },
        { name: "相机9",  node: cam1_4, station: "左侧工位", desc: "顶部正交点检" },
        { name: "相机6",  node: cam1_5, station: "左侧工位", desc: "轮面几何测量" },
        { name: "相机5",  node: cam1_6, station: "左侧工位", desc: "轮缘间隙测量" },
        // 右侧工位
        { name: "相机11", node: cam2_1, station: "右侧工位", desc: "斜俯视点检" },
        { name: "相机8",  node: cam2_2, station: "右侧工位", desc: "轮面几何测量" },
        { name: "相机12", node: cam2_3, station: "右侧工位", desc: "侧前视点检" },
        { name: "相机7",  node: cam2_4, station: "右侧工位", desc: "轮缘间隙测量" },
        { name: "相机4",  node: cam2_5, station: "右侧工位", desc: "侧后视点检" },
        { name: "相机3",  node: cam2_6, station: "右侧工位", desc: "顶部正交点检" }
    ]

    // 驱动轮数据列表 (3D 视图中白色轮组，对应点检驱动轮 1 ~ 8)
    readonly property var driveWheelList: [
        // 左侧工位
        { name: "驱动轮1", node: dw1, station: "左侧工位", desc: "驱动轮 #1 (前外侧)", color: "#38bdf8", quadrant: "前外", rail: "外轨" },
        { name: "驱动轮2", node: dw2, station: "左侧工位", desc: "驱动轮 #2 (后外侧)", color: "#38bdf8", quadrant: "后外", rail: "外轨" },
        { name: "驱动轮5", node: dw5, station: "左侧工位", desc: "驱动轮 #5 (前内侧)", color: "#38bdf8", quadrant: "前内", rail: "内轨" },
        { name: "驱动轮6", node: dw6, station: "左侧工位", desc: "驱动轮 #6 (后内侧)", color: "#38bdf8", quadrant: "后内", rail: "内轨" },
        // 右侧工位
        { name: "驱动轮3", node: dw3, station: "右侧工位", desc: "驱动轮 #3 (前外侧)", color: "#38bdf8", quadrant: "前外", rail: "外轨" },
        { name: "驱动轮4", node: dw4, station: "右侧工位", desc: "驱动轮 #4 (后外侧)", color: "#38bdf8", quadrant: "后外", rail: "外轨" },
        { name: "驱动轮7", node: dw7, station: "右侧工位", desc: "驱动轮 #7 (前内侧)", color: "#38bdf8", quadrant: "前内", rail: "内轨" },
        { name: "驱动轮8", node: dw8, station: "右侧工位", desc: "驱动轮 #8 (后内侧)", color: "#38bdf8", quadrant: "后内", rail: "内轨" }
    ]

    // 走行轮数据列表 (3D 视图中灰色轮组，对应点检走行轮 1 ~ 8 / 序号 11 ~ 18)
    readonly property var walkWheelList: [
        // 左侧工位
        { name: "走行轮1", node: ww1, station: "左侧工位", desc: "走行轮 #1 (前外侧/序号11)", color: "#fb923c", quadrant: "前外", rail: "外轨" },
        { name: "走行轮2", node: ww2, station: "左侧工位", desc: "走行轮 #2 (后外侧/序号12)", color: "#fb923c", quadrant: "后外", rail: "外轨" },
        { name: "走行轮5", node: ww5, station: "左侧工位", desc: "走行轮 #5 (前内侧/序号15)", color: "#fb923c", quadrant: "前内", rail: "内轨" },
        { name: "走行轮6", node: ww6, station: "左侧工位", desc: "走行轮 #6 (后内侧/序号16)", color: "#fb923c", quadrant: "后内", rail: "内轨" },
        // 右侧工位
        { name: "走行轮3", node: ww3, station: "右侧工位", desc: "走行轮 #3 (前外侧/序号13)", color: "#fb923c", quadrant: "前外", rail: "外轨" },
        { name: "走行轮4", node: ww4, station: "右侧工位", desc: "走行轮 #4 (后外侧/序号14)", color: "#fb923c", quadrant: "后外", rail: "外轨" },
        { name: "走行轮7", node: ww7, station: "右侧工位", desc: "走行轮 #7 (前内侧/序号17)", color: "#fb923c", quadrant: "前内", rail: "内轨" },
        { name: "走行轮8", node: ww8, station: "右侧工位", desc: "走行轮 #8 (后内侧/序号18)", color: "#fb923c", quadrant: "后内", rail: "内轨" }
    ]

    // 风格色彩方案 (黑/白 双主题体系)
    readonly property var styleThemes: [
        {
            name: "极夜黑",
            isDark: true,
            containerBg: "#070b12",
            bgTop: "#0b121e",
            bgMid: "#121d30",
            bgBottom: "#070a11",
            spotlight: "#1e3557",
            grid: "#1e3a5f",
            accent: "#00a3ff",
            bracket: "#38bdf8",
            cardBg: "#cc090e17",
            cardBorder: "#2638bdf8",
            dividerColor: "#334155",
            textPrimary: "#f8fafc",
            textSecondary: "#94a3b8",
            lightKey: "#ffffff",
            lightKeyBrightness: 1.2,
            lightFill: "#94b8db",
            lightFillBrightness: 0.55,
            lightRim: "#38bdf8",
            lightRimBrightness: 0.85,
            lightBounce: "#1e293b",
            lightBounceBrightness: 0.30,
            aoStrength: 60,
            aoDistance: 35,
            aoSoftness: 5
        },
        {
            name: "工业白",
            isDark: false,
            containerBg: "#f1f5f9",
            bgTop: "#f8fafc",
            bgMid: "#edf2f7",
            bgBottom: "#e2e8f0",
            spotlight: "#ffffff",
            grid: "#cbd5e1",
            accent: "#0284c7",
            bracket: "#94a3b8",
            cardBg: "#eef8fafc",
            cardBorder: "#cbd5e1",
            dividerColor: "#cbd5e1",
            textPrimary: "#0f172a",
            textSecondary: "#475569",
            lightKey: "#ffffff",
            lightKeyBrightness: 1.35,
            lightFill: "#dbeafe",
            lightFillBrightness: 0.85,
            lightRim: "#60a5fa",
            lightRimBrightness: 0.70,
            lightBounce: "#f1f5f9",
            lightBounceBrightness: 0.50,
            aoStrength: 35,
            aoDistance: 30,
            aoSoftness: 6
        }
    ]

    readonly property var curTheme: styleThemes[sceneStyle % styleThemes.length]

    Connections {
        target: Theme
        function onIsDarkChanged() {
            root.sceneStyle = Theme.isDark ? 0 : 1
            stageCanvas.requestPaint()
        }
    }

    Connections {
        target: typeof appController !== 'undefined' ? appController : null
        function onHomepageDescriptionChanged() {
            if (appController)
                root.descriptionText = appController.homepageDescription
        }
    }

    // 主容器卡片
    Rectangle {
        anchors.fill: parent
        radius: root.showHeader ? Theme.radiusLg : Theme.radiusMd
        color: Theme.bgCard
        border.width: root.showHeader ? 1 : 0
        border.color: Theme.borderMedium

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.showHeader ? 14 : 0
            spacing: root.showHeader ? 10 : 0

            // 顶部系统说明卡片 (仅独立展示时显示，嵌入首页时可收起)
            Rectangle {
                id: headerCard
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                visible: root.showHeader
                radius: Theme.radiusMd
                color: Theme.bgCardElevated
                border.width: 1
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    Rectangle { width: 4; height: 16; radius: 2; color: Theme.primary }

                    Label {
                        Layout.fillWidth: true
                        text: root.descriptionText || "Carrier 点检工位立体几何模型交互展示 · 高精度数字孪生渲染"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // 3D 渲染视窗舞台容器
            Rectangle {
                id: modelContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.showHeader ? Theme.radiusMd : 0
                clip: true
                color: root.curTheme.containerBg

                // 1. 底层影棚质感高动态渐变背景
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.curTheme.bgTop }
                        GradientStop { position: 0.55; color: root.curTheme.bgMid }
                        GradientStop { position: 1.0; color: root.curTheme.bgBottom }
                    }
                }

                // 2. 科技透视地面网格与同心圆标尺底盘 (Stage Canvas)
                Canvas {
                    id: stageCanvas
                    anchors.fill: parent
                    renderTarget: Canvas.Image

                    Connections {
                        target: root
                        function onSceneStyleChanged() { stageCanvas.requestPaint() }
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var cx = width * 0.5
                        var cy = height * 0.65 // 透视地台中心点

                        // A. 舞台中心径向微光聚光灯
                        var maxR = Math.max(width, height) * 0.65
                        var spotGrad = ctx.createRadialGradient(cx, cy, 10, cx, cy, maxR)
                        spotGrad.addColorStop(0, root.curTheme.spotlight)
                        spotGrad.addColorStop(0.7, root.curTheme.isDark ? "transparent" : "#00ffffff")
                        ctx.fillStyle = spotGrad
                        ctx.fillRect(0, 0, width, height)

                        // B. 3D 透视椭圆地台转盘
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.scale(1.0, 0.36) // 倾角压缩为3D地面椭圆

                        // 外圈标尺环
                        ctx.lineWidth = 1.2
                        ctx.strokeStyle = root.curTheme.grid
                        ctx.beginPath()
                        ctx.arc(0, 0, width * 0.42, 0, Math.PI * 2)
                        ctx.stroke()

                        // 中圈辅助环
                        ctx.lineWidth = 1.0
                        ctx.beginPath()
                        ctx.arc(0, 0, width * 0.28, 0, Math.PI * 2)
                        ctx.stroke()

                        // 内圈激光核心环
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = root.curTheme.accent
                        ctx.beginPath()
                        ctx.arc(0, 0, width * 0.15, 0, Math.PI * 2)
                        ctx.stroke()

                        // 十字定位经纬线
                        ctx.lineWidth = 1.0
                        ctx.strokeStyle = root.curTheme.grid
                        ctx.beginPath()
                        ctx.moveTo(-width * 0.46, 0)
                        ctx.lineTo(width * 0.46, 0)
                        ctx.moveTo(0, -width * 0.46)
                        ctx.lineTo(0, width * 0.46)
                        ctx.stroke()

                        ctx.restore()

                        // C. 四角工业科技标定线 (CAD Viewport Brackets)
                        var bSize = 14
                        var m = 12
                        ctx.strokeStyle = root.curTheme.bracket
                        ctx.lineWidth = 1.5

                        // 左上
                        ctx.beginPath()
                        ctx.moveTo(m, m + bSize); ctx.lineTo(m, m); ctx.lineTo(m + bSize, m)
                        ctx.stroke()
                        // 右上
                        ctx.beginPath()
                        ctx.moveTo(width - m - bSize, m); ctx.lineTo(width - m, m); ctx.lineTo(width - m, m + bSize)
                        ctx.stroke()
                        // 左下
                        ctx.beginPath()
                        ctx.moveTo(m, height - m - bSize); ctx.lineTo(m, height - m); ctx.lineTo(m + bSize, height - m)
                        ctx.stroke()
                        // 右下
                        ctx.beginPath()
                        ctx.moveTo(width - m - bSize, height - m); ctx.lineTo(width - m, height - m); ctx.lineTo(width - m, height - m - bSize)
                        ctx.stroke()
                    }
                }

                // 3. QtQuick3D 三维渲染引擎视窗
                View3D {
                    id: modelView
                    anchors.fill: parent
                    renderMode: View3D.Offscreen
                    camera: camera

                    // 高性能渲染环境管线 (高速4x MSAA + Filmic色调映射，避免全屏SSAO多通道后处理卡顿)
                    environment: SceneEnvironment {
                        backgroundMode: SceneEnvironment.Transparent
                        tonemapMode: SceneEnvironment.TonemapModeFilmic
                        antialiasingMode: SceneEnvironment.MSAA
                        antialiasingQuality: SceneEnvironment.Medium
                        specularAAEnabled: false
                        aoEnabled: false
                    }

                    PerspectiveCamera {
                        id: camera
                        position: Qt.vector3d(0, 0, 600)
                        fieldOfView: 45
                        onZChanged: modelContainer.updateTagPositions()
                    }

                    // 主光源 (Key Light: 暖白定向主光，投射真实柔和接触阴影)
                    DirectionalLight {
                        eulerRotation: Qt.vector3d(-40, -35, 0)
                        brightness: root.curTheme.lightKeyBrightness
                        color: root.curTheme.lightKey
                        castsShadow: false
                    }

                    // 补光源 (Fill Light: 柔和补光，提升机械结构暗部层次)
                    DirectionalLight {
                        eulerRotation: Qt.vector3d(45, 140, 0)
                        brightness: root.curTheme.lightFillBrightness
                        color: root.curTheme.lightFill
                    }

                    // 轮廓光 (Rim Light: 边缘切光，勾勒金属外壳精致高光)
                    DirectionalLight {
                        eulerRotation: Qt.vector3d(-20, 175, 0)
                        brightness: root.curTheme.lightRimBrightness
                        color: root.curTheme.lightRim
                    }

                    // 地面反弹微光 (Ground Bounce)
                    DirectionalLight {
                        eulerRotation: Qt.vector3d(70, 0, 0)
                        brightness: root.curTheme.lightBounceBrightness
                        color: root.curTheme.lightBounce
                    }

                    // 局部点光源 (Point Light: 强化局部景深高光)
                    PointLight {
                        position: Qt.vector3d(-150, 260, 320)
                        brightness: root.curTheme.isDark ? 45 : 55
                        color: root.curTheme.isDark ? "#e0f2fe" : "#ffffff"
                        linearFade: 0.5
                    }

                    // 内部相机与镜头专用补光 (Station 1 视觉工位特写补光)
                    PointLight {
                        position: Qt.vector3d(-100, 30, 160)
                        brightness: root.curTheme.isDark ? 65 : 75
                        color: "#ffffff"
                        linearFade: 0.6
                    }

                    // 内部相机与镜头专用补光 (Station 2 视觉工位特写补光)
                    PointLight {
                        position: Qt.vector3d(100, 30, 160)
                        brightness: root.curTheme.isDark ? 65 : 75
                        color: "#ffffff"
                        linearFade: 0.6
                    }

                    // 3D 枢轴节点与装配体模型加载器
                    Node {
                        id: modelPivot
                        property real pitch: 88
                        property real yaw: 0
                        property real panX: 0
                        property real panY: 0
                        position: Qt.vector3d(panX, panY, 0)
                        eulerRotation: Qt.vector3d(pitch, yaw, 0)
                        onPitchChanged: modelContainer.updateTagPositions()
                        onYawChanged: modelContainer.updateTagPositions()
                        onPanXChanged: modelContainer.updateTagPositions()
                        onPanYChanged: modelContainer.updateTagPositions()

                        // CAD 坐标系转换：原模型 Z 轴为垂直高度 (+Z 槽钢在顶，-Z 立柱在底)
                        // 绕 X 轴旋转 -90 度，映射至 QtQuick3D 世界坐标系 (+Y 为天空/+Z为深度)
                        Node {
                            id: modelBaseOrient
                            eulerRotation: Qt.vector3d(-90, 0, 0)

                            RuntimeLoader {
                                id: homeModel
                                source: "qrc:/qt/qml/CarrierVision/icons/Assembly.glb"

                                function fitToView() {
                                    var minimum = bounds.minimum
                                    var maximum = bounds.maximum
                                    var dx = maximum.x - minimum.x
                                    var dy = maximum.y - minimum.y
                                    var dz = maximum.z - minimum.z

                                    if (dx <= 0 || dy <= 0 || dz <= 0
                                        || modelView.width <= 0 || modelView.height <= 0)
                                        return

                                    // 模型经 Rx(-90) 转换后:
                                    // 物理跨度: 顺轨长轴 dx (约2.01m), 垂直高轴 dz (约0.61m, 槽钢在顶), 进深横轴 dy (约1.06m)
                                    // 综合兼顾俯视视角 (pitch ~88°, yaw ~0°) 及轴测视角的视窗投影外接包络
                                    var projWidth = Math.max(dx, dx * 0.906 + dy * 0.423)
                                    var projHeight = Math.max(dy, dz * 0.927 + (dx * 0.423 + dy * 0.906) * 0.375)

                                    var viewHeight = 2 * Math.abs(camera.z)
                                        * Math.tan(camera.fieldOfView * Math.PI / 360)
                                    var viewWidth = viewHeight * modelView.width / modelView.height
                                    var fitScale = Math.min(viewWidth * 0.78 / projWidth,
                                                viewHeight * 0.76 / projHeight)

                                    scale = Qt.vector3d(fitScale, fitScale, fitScale)
                                    position = Qt.vector3d(
                                        -(minimum.x + maximum.x) * fitScale / 2,
                                        -(minimum.y + maximum.y) * fitScale / 2,
                                        -(minimum.z + maximum.z) * fitScale / 2)
                                }

                                onStatusChanged: {
                                    if (status === RuntimeLoader.Success) {
                                        fitToView()
                                        Qt.callLater(modelContainer.updateTagPositions)
                                    }
                                }

                                onBoundsChanged: {
                                    if (status === RuntimeLoader.Success) {
                                        fitToView()
                                        Qt.callLater(modelContainer.updateTagPositions)
                                    }
                                }
                            }

                            // 相机物理空间定位锚点容器
                            Node {
                                id: cameraMarkersContainer
                                scale: homeModel.scale
                                position: homeModel.position

                                // 工位 1 (左侧点检工位 6 相机)
                                Node { id: cam1_1; position: Qt.vector3d(0.2698, 0.4152, 0.0100) }
                                Node { id: cam1_2; position: Qt.vector3d(0.2698, -0.3148, 0.0100) }
                                Node { id: cam1_3; position: Qt.vector3d(0.1487, -0.1552, 0.3029) }
                                Node { id: cam1_4; position: Qt.vector3d(0.0549, -0.1559, 0.3023) }
                                Node { id: cam1_5; position: Qt.vector3d(0.4777, 0.2717, 0.2904) }
                                Node { id: cam1_6; position: Qt.vector3d(0.3839, 0.2750, 0.2876) }

                                // 工位 2 (右侧点检工位 6 相机)
                                Node { id: cam2_1; position: Qt.vector3d(1.0679, -0.1543, 0.3028) }
                                Node { id: cam2_2; position: Qt.vector3d(1.4917, 0.2731, 0.2892) }
                                Node { id: cam2_3; position: Qt.vector3d(1.1627, -0.1552, 0.3029) }
                                Node { id: cam2_4; position: Qt.vector3d(1.3979, 0.2750, 0.2876) }
                                Node { id: cam2_5; position: Qt.vector3d(1.2838, -0.3148, 0.0100) }
                                Node { id: cam2_6; position: Qt.vector3d(1.2838, 0.4152, 0.0100) }
                            }

                            // 驱动轮与走行轮物理空间定位锚点容器
                            Node {
                                id: wheelMarkersContainer
                                scale: homeModel.scale
                                position: homeModel.position

                                // 驱动轮 (白色轮组, 轮2-x, 驱动轮 1 ~ 8)
                                Node { id: dw1; position: Qt.vector3d(0.2194, 0.0768, 0.0817) }
                                Node { id: dw2; position: Qt.vector3d(0.3132, 0.0768, 0.0817) }
                                Node { id: dw3; position: Qt.vector3d(1.2335, 0.0768, 0.0817) }
                                Node { id: dw4; position: Qt.vector3d(1.3273, 0.0768, 0.0817) }
                                Node { id: dw5; position: Qt.vector3d(0.2194, 0.0246, 0.0817) }
                                Node { id: dw6; position: Qt.vector3d(0.3132, 0.0246, 0.0817) }
                                Node { id: dw7; position: Qt.vector3d(1.2334, 0.0246, 0.0817) }
                                Node { id: dw8; position: Qt.vector3d(1.3272, 0.0246, 0.0817) }

                                // 走行轮 (灰色轮组, 轮1-x, 走行轮 1 ~ 8)
                                Node { id: ww1; position: Qt.vector3d(0.2375, 0.0872, 0.0100) }
                                Node { id: ww2; position: Qt.vector3d(0.3021, 0.0872, 0.0100) }
                                Node { id: ww3; position: Qt.vector3d(1.2515, 0.0872, 0.0100) }
                                Node { id: ww4; position: Qt.vector3d(1.3161, 0.0872, 0.0100) }
                                Node { id: ww5; position: Qt.vector3d(0.2375, 0.0132, 0.0100) }
                                Node { id: ww6; position: Qt.vector3d(0.3021, 0.0132, 0.0100) }
                                Node { id: ww7; position: Qt.vector3d(1.2515, 0.0132, 0.0100) }
                                Node { id: ww8; position: Qt.vector3d(1.3161, 0.0132, 0.0100) }
                            }
                        }
                    }

                    onWidthChanged: {
                        if (homeModel.status === RuntimeLoader.Success) {
                            homeModel.fitToView()
                            Qt.callLater(modelContainer.updateTagPositions)
                        }
                    }

                    onHeightChanged: {
                        if (homeModel.status === RuntimeLoader.Success) {
                            homeModel.fitToView()
                            Qt.callLater(modelContainer.updateTagPositions)
                        }
                    }
                }

                // 标签追踪实时刷新定时器 (动画播放期间启动)
                Timer {
                    id: tagUpdateTimer
                    interval: 20
                    repeat: true
                    running: false
                    onTriggered: modelContainer.updateTagPositions()
                }

                // 视角平滑过渡动画
                ParallelAnimation {
                    id: viewAnim
                    onRunningChanged: {
                        if (running) tagUpdateTimer.start()
                        else { tagUpdateTimer.stop(); modelContainer.updateTagPositions() }
                    }
                    NumberAnimation { id: pitchAnim; target: modelPivot; property: "pitch"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { id: yawAnim; target: modelPivot; property: "yaw"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { id: zAnim; target: camera; property: "z"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { id: panXAnim; target: modelPivot; property: "panX"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { id: panYAnim; target: modelPivot; property: "panY"; duration: 420; easing.type: Easing.OutCubic }
                }

                function animateToView(tPitch, tYaw, tZ, tPanX, tPanY) {
                    autoRotateTimer.running = false
                    viewAnim.stop()
                    pitchAnim.to = tPitch
                    yawAnim.to = tYaw
                    zAnim.to = tZ !== undefined ? tZ : 600
                    panXAnim.to = tPanX !== undefined ? tPanX : 0
                    panYAnim.to = tPanY !== undefined ? tPanY : 0
                    viewAnim.start()
                }

                // 自动巡航旋转定时器
                Timer {
                    id: autoRotateTimer
                    interval: 25
                    repeat: true
                    running: false
                    onTriggered: {
                        modelPivot.yaw = (modelPivot.yaw + 0.35) % 360
                        modelContainer.updateTagPositions()
                    }
                }

                // 鼠标交互控制层 (左键旋转，右键/中键/Shift+左键平移拖动，滚轮缩放)
                MouseArea {
                    id: rotationArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    property real lastX: 0
                    property real lastY: 0
                    property int activeButtons: 0
                    cursorShape: (activeButtons & (Qt.RightButton | Qt.MiddleButton)) ? Qt.SizeAllCursor
                                 : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

                    onPressed: function(mouse) {
                        root.selectedTag = ""
                        autoRotateTimer.running = false
                        viewAnim.stop()
                        activeButtons = mouse.buttons
                        lastX = mouse.x
                        lastY = mouse.y
                    }

                    onReleased: function(mouse) {
                        activeButtons = mouse.buttons
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed)
                            return

                        activeButtons = mouse.buttons
                        var dx = mouse.x - lastX
                        var dy = mouse.y - lastY

                        // 平移拖动模式：按住右键、中键、或按住Shift+左键
                        if ((mouse.buttons & Qt.RightButton) || (mouse.buttons & Qt.MiddleButton) || (mouse.modifiers & Qt.ShiftModifier)) {
                            var panFactor = Math.abs(camera.z) * 0.0016
                            modelPivot.panX += dx * panFactor
                            modelPivot.panY -= dy * panFactor
                        } else if (mouse.buttons & Qt.LeftButton) {
                            // 左键旋转模式
                            modelPivot.yaw += dx * 0.5
                            modelPivot.pitch = Math.max(-85, Math.min(85, modelPivot.pitch + dy * 0.5))
                        }

                        lastX = mouse.x
                        lastY = mouse.y
                        modelContainer.updateTagPositions()
                    }

                    onWheel: function(wheel) {
                        viewAnim.stop()
                        camera.z = Math.max(100, Math.min(2000,
                            camera.z - wheel.angleDelta.y * 0.4))
                        modelContainer.updateTagPositions()
                    }
                }

                // 视窗显隐或尺寸变化时自动刷新空间标签
                onVisibleChanged: {
                    if (visible) Qt.callLater(updateTagPositions)
                }

                Component.onCompleted: {
                    Qt.callLater(updateTagPositions)
                }

                // 启动阶段多级自适应触发定时器
                Timer { interval: 150; running: true; repeat: false; onTriggered: modelContainer.updateTagPositions() }
                Timer { interval: 400; running: true; repeat: false; onTriggered: modelContainer.updateTagPositions() }
                Timer { interval: 900; running: true; repeat: false; onTriggered: modelContainer.updateTagPositions() }

                // 统一空间标签坐标更新方法 (采用帧合并节流，避免高频鼠标拖拽产生多重投影矩阵阻塞)
                property bool _tagUpdatePending: false
                function updateTagPositions() {
                    if (_tagUpdatePending)
                        return
                    _tagUpdatePending = true
                    Qt.callLater(_doUpdateTagPositions)
                }

                function _doUpdateTagPositions() {
                    _tagUpdatePending = false

                    try {
                        var allTags = []
                        var vw = Math.max(modelView.width, 300)
                        var vh = Math.max(modelView.height, 200)

                        // ================= 1. 相机标签初算 (品红: 12 台相机，外围环绕) =================
                        if (root.showCameraLabels) {
                            var camOffsets = [
                                // 左工位 6 台相机: 侧前(1)、侧后(2)、斜俯(10)、正交顶(9)、轮面(6)、轮缘(5)
                                { dx: -130, dy:    0 }, // 相机1 (侧前 - 极左侧翼)
                                { dx:  130, dy:    0 }, // 相机2 (侧后 - 极右侧翼)
                                { dx:  -70, dy: -136 }, // 相机10 (斜俯 - 顶翼偏左)
                                { dx:    0, dy: -142 }, // 相机9 (正交顶 - 顶翼正中)
                                { dx:   70, dy: -136 }, // 相机6 (轮面 - 顶翼偏右)
                                { dx:    0, dy:  136 }, // 相机5 (轮缘 - 底翼正中)
                                // 右工位 6 台相机: 斜俯(11)、轮面(8)、侧前(12)、轮缘(7)、侧后(4)、正交顶(3)
                                { dx:  -70, dy: -136 }, // 相机11 (斜俯 - 顶翼偏左)
                                { dx:   70, dy: -136 }, // 相机8 (轮面 - 顶翼偏右)
                                { dx: -130, dy:    0 }, // 相机12 (侧前 - 极左侧翼)
                                { dx:    0, dy:  136 }, // 相机7 (轮缘 - 底翼正中)
                                { dx:  130, dy:    0 }, // 相机4 (侧后 - 极右侧翼)
                                { dx:    0, dy: -142 }  // 相机3 (正交顶 - 顶翼正中)
                            ]

                            for (var c = 0; c < cameraTagRepeater.count; ++c) {
                                var cItem = cameraTagRepeater.itemAt(c)
                                if (cItem && cItem.targetNode) {
                                    var cPos = modelView.mapFrom3DScene(cItem.targetNode.scenePosition)
                                    cItem.tagX = cPos.x
                                    cItem.tagY = cPos.y
                                    cItem.tagZ = cPos.z
                                    cItem.isInView = (cPos.z > 0 && cPos.x >= -150 && cPos.x <= vw + 150 && cPos.y >= -150 && cPos.y <= vh + 150)

                                    var cOff = camOffsets[c] || { dx: 0, dy: -32 }
                                    cItem.badgeCenterX = cPos.x + cOff.dx
                                    cItem.badgeCenterY = cPos.y + cOff.dy
                                    cItem.side = "outer"
                                    cItem.lr = "none"
                                    cItem.tagType = "cam"
                                    allTags.push(cItem)
                                }
                            }
                        }

                        // ================= 2. 驱动轮初算 (湛蓝: 驱动轮 1~8) =================
                        if (root.showDriveWheelLabels) {
                            // 严格对应 driveWheelList 顺序:
                            // [0]: dw1 (左前外), [1]: dw2 (左后外), [2]: dw5 (左前内), [3]: dw6 (左后内)
                            // [4]: dw3 (右前外), [5]: dw4 (右后外), [6]: dw7 (右前内), [7]: dw8 (右后内)
                            // 中层内环标高: 上轨(前外/后外)向上 -46px, 下轨(前内/后内)向下 +46px; 前侧向左 -54px, 后侧向右 +54px
                            var dwOffsets = [
                                { dx: -54, dy: -46, side: "top", lr: "left" },  // dw1 (左前外, 上轨中层)
                                { dx:  54, dy: -46, side: "top", lr: "right" }, // dw2 (左后外, 上轨中层)
                                { dx: -54, dy:  46, side: "bot", lr: "left" },  // dw5 (左前内, 下轨中层)
                                { dx:  54, dy:  46, side: "bot", lr: "right" }, // dw6 (左后内, 下轨中层)
                                { dx: -54, dy: -46, side: "top", lr: "left" },  // dw3 (右前外, 上轨中层)
                                { dx:  54, dy: -46, side: "top", lr: "right" }, // dw4 (右后外, 上轨中层)
                                { dx: -54, dy:  46, side: "bot", lr: "left" },  // dw7 (右前内, 下轨中层)
                                { dx:  54, dy:  46, side: "bot", lr: "right" }  // dw8 (右后内, 下轨中层)
                            ]

                            for (var d = 0; d < driveWheelTagRepeater.count; ++d) {
                                var dItem = driveWheelTagRepeater.itemAt(d)
                                if (dItem && dItem.targetNode) {
                                    var dPos = modelView.mapFrom3DScene(dItem.targetNode.scenePosition)
                                    dItem.tagX = dPos.x
                                    dItem.tagY = dPos.y
                                    dItem.tagZ = dPos.z
                                    dItem.isInView = (dPos.z > 0 && dPos.x >= -150 && dPos.x <= vw + 150 && dPos.y >= -150 && dPos.y <= vh + 150)

                                    var dOff = dwOffsets[d] || { dx: 0, dy: -28, side: "top", lr: "none" }
                                    dItem.badgeCenterX = dPos.x + dOff.dx
                                    dItem.badgeCenterY = dPos.y + dOff.dy
                                    dItem.side = dOff.side
                                    dItem.lr = dOff.lr
                                    dItem.tagType = "dw"
                                    allTags.push(dItem)
                                }
                            }
                        }

                        // ================= 3. 走行轮初算 (琥珀: 走行轮 1~8) =================
                        if (root.showWalkWheelLabels) {
                            // 严格对应 walkWheelList 顺序:
                            // [0]: ww1 (左前外), [1]: ww2 (左后外), [2]: ww5 (左前内), [3]: ww6 (左后内)
                            // [4]: ww3 (右前外), [5]: ww4 (右后外), [6]: ww7 (右前内), [7]: ww8 (右后内)
                            // 外层标高环: 上轨(前外/后外)向上 -90px, 下轨(前内/后内)向下 +90px; 前侧向左 -82px, 后侧向右 +82px
                            var wwOffsets = [
                                { dx: -82, dy: -90, side: "top", lr: "left" },  // ww1 (左前外, 上轨高层)
                                { dx:  82, dy: -90, side: "top", lr: "right" }, // ww2 (左后外, 上轨高层)
                                { dx: -82, dy:  90, side: "bot", lr: "left" },  // ww5 (左前内, 下轨深层)
                                { dx:  82, dy:  90, side: "bot", lr: "right" }, // ww6 (左后内, 下轨深层)
                                { dx: -82, dy: -90, side: "top", lr: "left" },  // ww3 (右前外, 上轨高层)
                                { dx:  82, dy: -90, side: "top", lr: "right" }, // ww4 (右后外, 上轨高层)
                                { dx: -82, dy:  90, side: "bot", lr: "left" },  // ww7 (右前内, 下轨深层)
                                { dx:  82, dy:  90, side: "bot", lr: "right" }  // ww8 (右后内, 下轨深层)
                            ]

                            for (var w = 0; w < walkWheelTagRepeater.count; ++w) {
                                var wItem = walkWheelTagRepeater.itemAt(w)
                                if (wItem && wItem.targetNode) {
                                    var wPos = modelView.mapFrom3DScene(wItem.targetNode.scenePosition)
                                    wItem.tagX = wPos.x
                                    wItem.tagY = wPos.y
                                    wItem.tagZ = wPos.z
                                    wItem.isInView = (wPos.z > 0 && wPos.x >= -150 && wPos.x <= vw + 150 && wPos.y >= -150 && wPos.y <= vh + 150)

                                    var wOff = wwOffsets[w] || { dx: 0, dy: 32, side: "bot", lr: "none" }
                                    wItem.badgeCenterX = wPos.x + wOff.dx
                                    wItem.badgeCenterY = wPos.y + wOff.dy
                                    wItem.side = wOff.side
                                    wItem.lr = wOff.lr
                                    wItem.tagType = "ww"
                                    allTags.push(wItem)
                                }
                            }
                        }

                        // ================= 4. 保拓扑定向微调求解器 (Topology-Preserving Relaxer) =================
                        var minGapX = 76
                        var minGapY = 22
                        for (var iter = 0; iter < 4; ++iter) {
                            var moved = false
                            for (var i = 0; i < allTags.length; ++i) {
                                var tA = allTags[i]
                                if (!tA.isInView) continue
                                for (var j = i + 1; j < allTags.length; ++j) {
                                    var tB = allTags[j]
                                    if (!tB.isInView) continue

                                    var diffX = tB.badgeCenterX - tA.badgeCenterX
                                    var diffY = tB.badgeCenterY - tA.badgeCenterY

                                    if (Math.abs(diffX) < minGapX && Math.abs(diffY) < minGapY) {
                                        var shiftX = (minGapX - Math.abs(diffX)) * 0.5
                                        var shiftY = (minGapY - Math.abs(diffY)) * 0.5
                                        var sX = diffX >= 0 ? 1 : -1
                                        var sY = diffY >= 0 ? 1 : -1

                                        if (Math.abs(diffY) > 0.01) {
                                            tA.badgeCenterY -= shiftY * sY * 0.5
                                            tB.badgeCenterY += shiftY * sY * 0.5
                                        }
                                        if (Math.abs(diffX) > 0.01) {
                                            tA.badgeCenterX -= shiftX * sX * 0.4
                                            tB.badgeCenterX += shiftX * sX * 0.4
                                        }
                                        moved = true
                                    }
                                }
                            }
                            if (!moved) break
                        }

                        // ================= 5. 极性保护与视口安全边缘约束 =================
                        var padX = 45
                        var padY = 22
                        for (var k = 0; k < allTags.length; ++k) {
                            var tag = allTags[k]
                            if (tag.isInView) {
                                // 极性保护：上轨轮位永远在轮心上方，下轨轮位永远在轮心下方
                                if (tag.side === "top") {
                                    tag.badgeCenterY = Math.min(tag.badgeCenterY, tag.tagY - 12)
                                } else if (tag.side === "bot") {
                                    tag.badgeCenterY = Math.max(tag.badgeCenterY, tag.tagY + 12)
                                }

                                // 屏幕边界
                                tag.badgeCenterX = Math.max(padX, Math.min(vw - padX, tag.badgeCenterX))
                                tag.badgeCenterY = Math.max(padY, Math.min(vh - padY, tag.badgeCenterY))
                            }
                        }
                    } catch (err) {
                        console.warn("[DesignShowCore] _doUpdateTagPositions exception:", err)
                    }
                }

                // 3D 浮动标签层 (Floating 3D Tags: Cameras, Drive Wheels, Walk Wheels)
                Item {
                    id: tagOverlayLayer
                    anchors.fill: parent

                    // 1. 相机标签组
                    Repeater {
                        id: cameraTagRepeater
                        model: root.cameraList

                        Item {
                            id: camTagItem
                            property var targetNode: modelData.node
                            property real tagX: 0
                            property real tagY: 0
                            property real tagZ: 0
                            property real badgeCenterX: tagX
                            property real badgeCenterY: tagY - 24
                            property bool isInView: false
                            property string side: "outer"
                            property string lr: "none"
                            property string tagType: "cam"
                            readonly property bool isHit: (root.selectedTag === modelData.name) || camTagMouse.containsMouse

                            visible: root.showCameraLabels && isInView
                            opacity: (root.showCameraLabels && isInView) ? 1.0 : 0.0
                            z: isHit ? 100 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            // 1. 3D 定位品红点 (Pinpoint)
                            Rectangle {
                                x: camTagItem.tagX - 3.5
                                y: camTagItem.tagY - 3.5
                                width: 7
                                height: 7
                                radius: 3.5
                                color: camTagItem.isHit ? "#f43f5e" : "#e11d48"
                                border.width: 1
                                border.color: camTagItem.isHit ? "#ffffff" : (root.curTheme.isDark ? "#fca5a5" : "#ffffff")

                                Behavior on color { ColorAnimation { duration: 160 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: camTagItem.isHit ? 14 : 11
                                    height: camTagItem.isHit ? 14 : 11
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: camTagItem.isHit ?
                                                     (root.curTheme.isDark ? "#80fb7185" : "#80f43f5e") :
                                                     (root.curTheme.isDark ? "#33e11d48" : "#40e11d48")
                                    Behavior on width { NumberAnimation { duration: 160 } }
                                    Behavior on height { NumberAnimation { duration: 160 } }
                                    Behavior on border.color { ColorAnimation { duration: 160 } }
                                }
                            }

                            // 2. 正交微引线 (垂直段与水平折线段)
                            Rectangle {
                                x: camTagItem.tagX - 0.5
                                y: Math.min(camTagItem.tagY, camTagItem.badgeCenterY)
                                width: 1
                                height: Math.max(1, Math.abs(camTagItem.tagY - camTagItem.badgeCenterY))
                                color: camTagItem.isHit ?
                                           (root.curTheme.isDark ? "#fb7185" : "#e11d48") :
                                           (root.curTheme.isDark ? "#4de11d48" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Rectangle {
                                x: Math.min(camTagItem.tagX, camTagItem.badgeCenterX)
                                y: camTagItem.badgeCenterY - 0.5
                                width: Math.max(1, Math.abs(camTagItem.badgeCenterX - camTagItem.tagX))
                                height: 1
                                visible: Math.abs(camTagItem.badgeCenterX - camTagItem.tagX) > 2
                                color: camTagItem.isHit ?
                                           (root.curTheme.isDark ? "#fb7185" : "#e11d48") :
                                           (root.curTheme.isDark ? "#4de11d48" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            // 3. 悬浮标签胶囊 (Tag Badge)
                            Rectangle {
                                id: camBadgeBox
                                x: camTagItem.badgeCenterX - width / 2
                                y: camTagItem.badgeCenterY - height / 2
                                implicitWidth: camBadgeRow.implicitWidth + 14
                                implicitHeight: 22
                                radius: Theme.radiusPill
                                scale: camTagItem.isHit ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                                color: root.curTheme.isDark ?
                                           (camTagItem.isHit ? "#e61a2333" : "#b30b121e") :
                                           (camTagItem.isHit ? "#fff1f2" : "#eef8fafc")
                                border.width: camTagItem.isHit ? 2 : 1
                                border.color: root.curTheme.isDark ?
                                                  (camTagItem.isHit ? "#fb7185" : "#33e11d48") :
                                                  (camTagItem.isHit ? "#fda4af" : "#cbd5e1")

                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }

                                RowLayout {
                                    id: camBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Rectangle {
                                        width: 5; height: 5; radius: 2.5
                                        color: camTagItem.isHit ? "#f43f5e" : "#e11d48"
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Label {
                                        text: modelData.name
                                        color: root.curTheme.isDark ?
                                                   (camTagItem.isHit ? "#ffffff" : "#cbd5e1") :
                                                   (camTagItem.isHit ? "#be123c" : "#475569")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeTiny
                                        font.bold: true
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }
                                }

                                MouseArea {
                                    id: camTagMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedTag = (root.selectedTag === modelData.name ? "" : modelData.name)
                                    }
                                }

                                ToolTip.visible: camTagMouse.containsMouse
                                ToolTip.text: modelData.station + " · " + modelData.name + " (" + modelData.desc + ")"
                            }
                        }
                    }

                    // 2. 驱动轮标签组 (蓝色轮组 驱动轮1 ~ 8)
                    Repeater {
                        id: driveWheelTagRepeater
                        model: root.driveWheelList

                        Item {
                            id: dwTagItem
                            property var targetNode: modelData.node
                            property real tagX: 0
                            property real tagY: 0
                            property real tagZ: 0
                            property real badgeCenterX: tagX
                            property real badgeCenterY: tagY - 24
                            property bool isInView: false
                            property string side: "top"
                            property string lr: "none"
                            property string tagType: "dw"
                            readonly property bool isHit: (root.selectedTag === modelData.name) || dwTagMouse.containsMouse

                            visible: root.showDriveWheelLabels && isInView
                            opacity: (root.showDriveWheelLabels && isInView) ? 1.0 : 0.0
                            z: isHit ? 100 : 2
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            // 1. 定位湛蓝点 (Pinpoint)
                            Rectangle {
                                x: dwTagItem.tagX - 3.5
                                y: dwTagItem.tagY - 3.5
                                width: 7
                                height: 7
                                radius: 3.5
                                color: dwTagItem.isHit ? "#60a5fa" : "#2563eb"
                                border.width: 1
                                border.color: dwTagItem.isHit ? "#ffffff" : (root.curTheme.isDark ? "#93c5fd" : "#ffffff")

                                Behavior on color { ColorAnimation { duration: 160 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: dwTagItem.isHit ? 14 : 11
                                    height: dwTagItem.isHit ? 14 : 11
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: dwTagItem.isHit ?
                                                     (root.curTheme.isDark ? "#8060a5fa" : "#803b82f6") :
                                                     (root.curTheme.isDark ? "#333b82f6" : "#402563eb")
                                    Behavior on width { NumberAnimation { duration: 160 } }
                                    Behavior on height { NumberAnimation { duration: 160 } }
                                    Behavior on border.color { ColorAnimation { duration: 160 } }
                                }
                            }

                            // 2. 正交微引线 (垂直段与水平折线段)
                            Rectangle {
                                x: dwTagItem.tagX - 0.5
                                y: Math.min(dwTagItem.tagY, dwTagItem.badgeCenterY)
                                width: 1
                                height: Math.max(1, Math.abs(dwTagItem.tagY - dwTagItem.badgeCenterY))
                                color: dwTagItem.isHit ?
                                           (root.curTheme.isDark ? "#60a5fa" : "#2563eb") :
                                           (root.curTheme.isDark ? "#4d3b82f6" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Rectangle {
                                x: Math.min(dwTagItem.tagX, dwTagItem.badgeCenterX)
                                y: dwTagItem.badgeCenterY - 0.5
                                width: Math.max(1, Math.abs(dwTagItem.badgeCenterX - dwTagItem.tagX))
                                height: 1
                                visible: Math.abs(dwTagItem.badgeCenterX - dwTagItem.tagX) > 2
                                color: dwTagItem.isHit ?
                                           (root.curTheme.isDark ? "#60a5fa" : "#2563eb") :
                                           (root.curTheme.isDark ? "#4d3b82f6" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            // 3. 悬浮标签胶囊 (Tag Badge)
                            Rectangle {
                                id: dwBadgeBox
                                x: dwTagItem.badgeCenterX - width / 2
                                y: dwTagItem.badgeCenterY - height / 2
                                implicitWidth: dwBadgeRow.implicitWidth + 14
                                implicitHeight: 22
                                radius: Theme.radiusPill
                                scale: dwTagItem.isHit ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                                color: root.curTheme.isDark ?
                                           (dwTagItem.isHit ? "#e61a2538" : "#b30b121e") :
                                           (dwTagItem.isHit ? "#eff6ff" : "#eef8fafc")
                                border.width: dwTagItem.isHit ? 2 : 1
                                border.color: root.curTheme.isDark ?
                                                  (dwTagItem.isHit ? "#60a5fa" : "#333b82f6") :
                                                  (dwTagItem.isHit ? "#93c5fd" : "#cbd5e1")

                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }

                                // 选中高亮脉冲呼吸光环
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + 8
                                    height: parent.height + 8
                                    radius: parent.radius + 4
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: root.curTheme.isDark ? "#8060a5fa" : "#803b82f6"
                                    visible: dwTagItem.isHit
                                    SequentialAnimation on opacity {
                                        running: dwTagItem.isHit
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.9; to: 0.2; duration: 900; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.2; to: 0.9; duration: 900; easing.type: Easing.InOutQuad }
                                    }
                                }

                                RowLayout {
                                    id: dwBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Rectangle {
                                        width: 5; height: 5; radius: 2.5
                                        color: dwTagItem.isHit ? "#60a5fa" : "#2563eb"
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Label {
                                        text: modelData.name
                                        color: root.curTheme.isDark ?
                                                   (dwTagItem.isHit ? "#ffffff" : "#cbd5e1") :
                                                   (dwTagItem.isHit ? "#1d4ed8" : "#475569")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeTiny
                                        font.bold: true
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Rectangle {
                                        visible: Boolean(modelData.quadrant)
                                        implicitWidth: dwQuadLabel.implicitWidth + 6
                                        implicitHeight: 14
                                        radius: 3
                                        color: root.curTheme.isDark ? "#2638bdf8" : "#e0f2fe"

                                        Label {
                                            id: dwQuadLabel
                                            anchors.centerIn: parent
                                            text: modelData.quadrant || ""
                                            color: root.curTheme.isDark ? "#93c5fd" : "#0369a1"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontMicro
                                            font.weight: Theme.weightMedium
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dwTagMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedTag = (root.selectedTag === modelData.name ? "" : modelData.name)
                                    }
                                }

                                ToolTip.visible: dwTagMouse.containsMouse
                                ToolTip.text: modelData.station + " · " + modelData.name + " (" + (modelData.quadrant ? (modelData.quadrant + "侧 · ") : "") + (modelData.rail ? (modelData.rail + " · ") : "") + modelData.desc + ")"
                            }
                        }
                    }

                    // 3. 走行轮标签组 (琥珀轮组 走行轮1 ~ 8)
                    Repeater {
                        id: walkWheelTagRepeater
                        model: root.walkWheelList

                        Item {
                            id: wwTagItem
                            property var targetNode: modelData.node
                            property real tagX: 0
                            property real tagY: 0
                            property real tagZ: 0
                            property real badgeCenterX: tagX
                            property real badgeCenterY: tagY + 24
                            property bool isInView: false
                            property string side: "bot"
                            property string lr: "none"
                            property string tagType: "ww"
                            readonly property bool isHit: (root.selectedTag === modelData.name) || wwTagMouse.containsMouse

                            visible: root.showWalkWheelLabels && isInView
                            opacity: (root.showWalkWheelLabels && isInView) ? 1.0 : 0.0
                            z: isHit ? 100 : 3
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            // 1. 定位琥珀点 (Pinpoint)
                            Rectangle {
                                x: wwTagItem.tagX - 3.5
                                y: wwTagItem.tagY - 3.5
                                width: 7
                                height: 7
                                radius: 3.5
                                color: wwTagItem.isHit ? "#fbbf24" : "#d97706"
                                border.width: 1
                                border.color: wwTagItem.isHit ? "#ffffff" : (root.curTheme.isDark ? "#fde68a" : "#ffffff")

                                Behavior on color { ColorAnimation { duration: 160 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: wwTagItem.isHit ? 14 : 11
                                    height: wwTagItem.isHit ? 14 : 11
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: wwTagItem.isHit ?
                                                     (root.curTheme.isDark ? "#80fbbf24" : "#80f59e0b") :
                                                     (root.curTheme.isDark ? "#33f59e0b" : "#40d97706")
                                    Behavior on width { NumberAnimation { duration: 160 } }
                                    Behavior on height { NumberAnimation { duration: 160 } }
                                    Behavior on border.color { ColorAnimation { duration: 160 } }
                                }
                            }

                            // 2. 正交微引线 (向下垂直段与水平折线段)
                            Rectangle {
                                x: wwTagItem.tagX - 0.5
                                y: Math.min(wwTagItem.tagY, wwTagItem.badgeCenterY)
                                width: 1
                                height: Math.max(1, Math.abs(wwTagItem.tagY - wwTagItem.badgeCenterY))
                                color: wwTagItem.isHit ?
                                           (root.curTheme.isDark ? "#fbbf24" : "#d97706") :
                                           (root.curTheme.isDark ? "#4df59e0b" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Rectangle {
                                x: Math.min(wwTagItem.tagX, wwTagItem.badgeCenterX)
                                y: wwTagItem.badgeCenterY - 0.5
                                width: Math.max(1, Math.abs(wwTagItem.badgeCenterX - wwTagItem.tagX))
                                height: 1
                                visible: Math.abs(wwTagItem.badgeCenterX - wwTagItem.tagX) > 2
                                color: wwTagItem.isHit ?
                                           (root.curTheme.isDark ? "#fbbf24" : "#d97706") :
                                           (root.curTheme.isDark ? "#4df59e0b" : "#94a3b8")
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }

                            // 3. 悬浮标签胶囊 (Tag Badge: 位于定位点下方)
                            Rectangle {
                                id: wwBadgeBox
                                x: wwTagItem.badgeCenterX - width / 2
                                y: wwTagItem.badgeCenterY - height / 2
                                implicitWidth: wwBadgeRow.implicitWidth + 14
                                implicitHeight: 22
                                radius: Theme.radiusPill
                                scale: wwTagItem.isHit ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                                color: root.curTheme.isDark ?
                                           (wwTagItem.isHit ? "#e626211d" : "#b30b121e") :
                                           (wwTagItem.isHit ? "#fffbeb" : "#eef8fafc")
                                border.width: wwTagItem.isHit ? 2 : 1
                                border.color: root.curTheme.isDark ?
                                                  (wwTagItem.isHit ? "#fbbf24" : "#33f59e0b") :
                                                  (wwTagItem.isHit ? "#fde68a" : "#cbd5e1")

                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on border.color { ColorAnimation { duration: 160 } }

                                // 选中高亮脉冲呼吸光环
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + 8
                                    height: parent.height + 8
                                    radius: parent.radius + 4
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: root.curTheme.isDark ? "#80fbbf24" : "#80d97706"
                                    visible: wwTagItem.isHit
                                    SequentialAnimation on opacity {
                                        running: wwTagItem.isHit
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.9; to: 0.2; duration: 900; easing.type: Easing.InOutQuad }
                                        NumberAnimation { from: 0.2; to: 0.9; duration: 900; easing.type: Easing.InOutQuad }
                                    }
                                }

                                RowLayout {
                                    id: wwBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Rectangle {
                                        width: 5; height: 5; radius: 2.5
                                        color: wwTagItem.isHit ? "#fbbf24" : "#d97706"
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Label {
                                        text: modelData.name
                                        color: root.curTheme.isDark ?
                                                   (wwTagItem.isHit ? "#ffffff" : "#cbd5e1") :
                                                   (wwTagItem.isHit ? "#b45309" : "#475569")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeTiny
                                        font.bold: true
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                    }

                                    Rectangle {
                                        visible: Boolean(modelData.quadrant)
                                        implicitWidth: wwQuadLabel.implicitWidth + 6
                                        implicitHeight: 14
                                        radius: 3
                                        color: root.curTheme.isDark ? "#33f97316" : "#ffedd5"

                                        Label {
                                            id: wwQuadLabel
                                            anchors.centerIn: parent
                                            text: modelData.quadrant || ""
                                            color: root.curTheme.isDark ? "#fdba74" : "#c2410c"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontMicro
                                            font.weight: Theme.weightMedium
                                        }
                                    }
                                }

                                MouseArea {
                                    id: wwTagMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedTag = (root.selectedTag === modelData.name ? "" : modelData.name)
                                    }
                                }

                                ToolTip.visible: wwTagMouse.containsMouse
                                ToolTip.text: modelData.station + " · " + modelData.name + " (" + (modelData.quadrant ? (modelData.quadrant + "侧 · ") : "") + (modelData.rail ? (modelData.rail + " · ") : "") + modelData.desc + ")"
                            }
                        }
                    }
                }

                // ========== 4. 浮动 HUD 科技操作面板 ==========

                // 左上角：姿态与状态读数芯片 (收敛精简，鼠标悬停查看完整数值)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 14
                    radius: Theme.radiusPill
                    color: root.curTheme.cardBg
                    border.color: root.curTheme.cardBorder
                    border.width: 1
                    implicitWidth: infoRow.implicitWidth + 20
                    implicitHeight: 32

                    RowLayout {
                        id: infoRow
                        anchors.centerIn: parent
                        spacing: 7

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: "#10b981"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.4; to: 1.0; duration: 800 }
                                NumberAnimation { from: 1.0; to: 0.4; duration: 800 }
                            }
                        }

                        Label {
                            text: "3D TWIN"
                            color: root.curTheme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Rectangle { width: 1; height: 10; color: root.curTheme.dividerColor }

                        Label {
                            text: Math.round(modelPivot.pitch) + "° / " + Math.round(modelPivot.yaw) + "°"
                            color: root.curTheme.textSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    MouseArea {
                        id: infoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip.visible: infoMouse.containsMouse
                    ToolTip.text: "当前视角姿态 ╎ 俯仰: " + Math.round(modelPivot.pitch) + "° ╎ 航向: " + Math.round(modelPivot.yaw) + "° ╎ 深度视距: " + Math.round(600 / camera.z * 100) + "%"
                }

                // 右上角：交互工具栏 (收敛折叠架构：巡航、视角下拉、标签下拉、缩放胶囊、主题、复位)
                Rectangle {
                    id: topHudBar
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    radius: Theme.radiusPill
                    color: root.curTheme.cardBg
                    border.color: root.curTheme.cardBorder
                    border.width: 1
                    implicitHeight: 32
                    implicitWidth: toolRow.implicitWidth + 14

                    RowLayout {
                        id: toolRow
                        anchors.centerIn: parent
                        spacing: 4

                        // 1. 自动巡航开关
                        Rectangle {
                            implicitWidth: 58
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: autoRotateTimer.running ? (root.curTheme.isDark ? "#330284c7" : "#1f0284c7") : (cruiseMouse.containsMouse ? (root.curTheme.isDark ? "#20ffffff" : "#15000000") : "transparent")
                            border.width: autoRotateTimer.running ? 1 : 0
                            border.color: root.curTheme.accent

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: autoRotateTimer.running ? "⏸" : "🔄"
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: "巡航"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: autoRotateTimer.running ? root.curTheme.accent : root.curTheme.textSecondary
                                    font.bold: autoRotateTimer.running
                                }
                            }

                            MouseArea {
                                id: cruiseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: autoRotateTimer.running = !autoRotateTimer.running
                            }
                            ToolTip.visible: cruiseMouse.containsMouse
                            ToolTip.text: autoRotateTimer.running ? "暂停自动环绕巡航" : "开始 360° 自动环绕巡航"
                        }

                        Rectangle { width: 1; height: 12; color: root.curTheme.dividerColor }

                        // 2. 视角预设下拉菜单
                        Rectangle {
                            id: viewBtn
                            implicitWidth: 62
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: (viewPopup.visible || viewMouse.containsMouse) ? (root.curTheme.isDark ? "#20ffffff" : "#15000000") : "transparent"
                            border.width: viewPopup.visible ? 1 : 0
                            border.color: root.curTheme.accent

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 3
                                Text { text: "📐"; font.pixelSize: 10 }
                                Text {
                                    text: "视角 ▾"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: viewPopup.visible ? root.curTheme.accent : root.curTheme.textPrimary
                                    font.bold: viewPopup.visible
                                }
                            }

                            MouseArea {
                                id: viewMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (labelPopup.visible) labelPopup.close()
                                    if (viewPopup.visible) viewPopup.close()
                                    else viewPopup.open()
                                }
                            }
                            ToolTip.visible: viewMouse.containsMouse && !viewPopup.visible
                            ToolTip.text: "选择标准观测视角 (轴测/工位/正交)"

                            Popup {
                                id: viewPopup
                                y: viewBtn.height + 6
                                x: (viewBtn.width - width) / 2
                                width: 148
                                padding: 6
                                modal: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                background: Rectangle {
                                    radius: Theme.radiusMd
                                    color: root.curTheme.cardBg
                                    border.color: root.curTheme.cardBorder
                                    border.width: 1
                                }

                                contentItem: ColumnLayout {
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { name: "俯视鸟瞰 (顶梁)", icon: "⬇️", pitch: 88, yaw: 0, z: 600 },
                                            { name: "轴测视角 (全览)", icon: "📐", pitch: 22, yaw: 25, z: 600 },
                                            { name: "工位特写 (相机)", icon: "🎯", pitch: 14, yaw: 30, z: 350 },
                                            { name: "正视立面 (正面)", icon: "👁️", pitch: 0, yaw: 0, z: 600 },
                                            { name: "侧视截面 (侧面)", icon: "➡️", pitch: 0, yaw: 90, z: 600 }
                                        ]

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 28
                                            radius: 4
                                            color: itemMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6

                                                Text {
                                                    text: modelData.icon
                                                    font.pixelSize: 11
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: modelData.name
                                                    color: itemMouse.containsMouse ? root.curTheme.accent : root.curTheme.textPrimary
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fontSizeSmall
                                                }
                                            }

                                            MouseArea {
                                                id: itemMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    modelContainer.animateToView(modelData.pitch, modelData.yaw, modelData.z)
                                                    viewPopup.close()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: 1; height: 12; color: root.curTheme.dividerColor }

                        // 3. 标签图层下拉开关
                        Rectangle {
                            id: labelBtn
                            implicitWidth: 62
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: (labelPopup.visible || labelMouse.containsMouse) ? (root.curTheme.isDark ? "#20ffffff" : "#15000000") : "transparent"
                            border.width: labelPopup.visible ? 1 : 0
                            border.color: root.curTheme.accent

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 3
                                Text { text: "🏷️"; font.pixelSize: 10 }
                                Text {
                                    text: "标签 ▾"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: (root.showCameraLabels || root.showDriveWheelLabels || root.showWalkWheelLabels) ?
                                               (labelPopup.visible ? root.curTheme.accent : root.curTheme.textPrimary) :
                                               root.curTheme.textSecondary
                                    font.bold: labelPopup.visible
                                }
                            }

                            MouseArea {
                                id: labelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (viewPopup.visible) viewPopup.close()
                                    if (labelPopup.visible) labelPopup.close()
                                    else labelPopup.open()
                                }
                            }
                            ToolTip.visible: labelMouse.containsMouse && !labelPopup.visible
                            ToolTip.text: "管理 3D 空间标签图层显示"

                            Popup {
                                id: labelPopup
                                y: labelBtn.height + 6
                                x: (labelBtn.width - width) / 2
                                width: 165
                                padding: 6
                                modal: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                background: Rectangle {
                                    radius: Theme.radiusMd
                                    color: root.curTheme.cardBg
                                    border.color: root.curTheme.cardBorder
                                    border.width: 1
                                }

                                contentItem: ColumnLayout {
                                    spacing: 2

                                    // 相机
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 4
                                        color: camRowMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Text {
                                                text: root.showCameraLabels ? "☑" : "☐"
                                                font.pixelSize: 12
                                                color: root.showCameraLabels ? "#ef4444" : root.curTheme.textSecondary
                                            }

                                            Text { text: "📷"; font.pixelSize: 11 }

                                            Label {
                                                Layout.fillWidth: true
                                                text: "相机标签 (12台)"
                                                color: root.showCameraLabels ? (root.curTheme.isDark ? "#f87171" : "#dc2626") : root.curTheme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: root.showCameraLabels
                                            }
                                        }

                                        MouseArea {
                                            id: camRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.showCameraLabels = !root.showCameraLabels
                                                if (root.showCameraLabels)
                                                    Qt.callLater(modelContainer.updateTagPositions)
                                            }
                                        }
                                    }

                                    // 驱动轮
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 4
                                        color: dwRowMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Text {
                                                text: root.showDriveWheelLabels ? "☑" : "☐"
                                                font.pixelSize: 12
                                                color: root.showDriveWheelLabels ? root.curTheme.accent : root.curTheme.textSecondary
                                            }

                                            Text { text: "⚙"; font.pixelSize: 11 }

                                            Label {
                                                Layout.fillWidth: true
                                                text: "驱动轮 (8处)"
                                                color: root.showDriveWheelLabels ? root.curTheme.accent : root.curTheme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: root.showDriveWheelLabels
                                            }
                                        }

                                        MouseArea {
                                            id: dwRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.showDriveWheelLabels = !root.showDriveWheelLabels
                                                if (root.showDriveWheelLabels)
                                                    Qt.callLater(modelContainer.updateTagPositions)
                                            }
                                        }
                                    }

                                    // 走行轮
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 4
                                        color: wwRowMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 6

                                            Text {
                                                text: root.showWalkWheelLabels ? "☑" : "☐"
                                                font.pixelSize: 12
                                                color: root.showWalkWheelLabels ? "#ea580c" : root.curTheme.textSecondary
                                            }

                                            Text { text: "⭕"; font.pixelSize: 11 }

                                            Label {
                                                Layout.fillWidth: true
                                                text: "走行轮 (8处)"
                                                color: root.showWalkWheelLabels ? (root.curTheme.isDark ? "#fb923c" : "#ea580c") : root.curTheme.textPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: root.showWalkWheelLabels
                                            }
                                        }

                                        MouseArea {
                                            id: wwRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.showWalkWheelLabels = !root.showWalkWheelLabels
                                                if (root.showWalkWheelLabels)
                                                    Qt.callLater(modelContainer.updateTagPositions)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: root.curTheme.dividerColor
                                    }

                                    // 全显/全隐快捷行
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 2
                                        Layout.leftMargin: 4
                                        Layout.rightMargin: 4
                                        spacing: 4

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 22
                                            radius: 3
                                            color: allShowMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "全显"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeTiny
                                                color: root.curTheme.accent
                                            }
                                            MouseArea {
                                                id: allShowMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.showCameraLabels = true
                                                    root.showDriveWheelLabels = true
                                                    root.showWalkWheelLabels = true
                                                    Qt.callLater(modelContainer.updateTagPositions)
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 22
                                            radius: 3
                                            color: allHideMouse.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#12000000") : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "全隐"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeTiny
                                                color: root.curTheme.textSecondary
                                            }
                                            MouseArea {
                                                id: allHideMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.showCameraLabels = false
                                                    root.showDriveWheelLabels = false
                                                    root.showWalkWheelLabels = false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { width: 1; height: 12; color: root.curTheme.dividerColor }

                        // 4. 紧凑一体化缩放胶囊 [ ＋ | － ]
                        Rectangle {
                            implicitWidth: 48
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: root.curTheme.isDark ? "#14ffffff" : "#0a000000"
                            border.width: 1
                            border.color: root.curTheme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                // ＋ 放大
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusPill
                                        color: zoomInArea.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#18000000") : "transparent"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "＋"
                                        font.pixelSize: 12
                                        color: root.curTheme.textPrimary
                                    }
                                    MouseArea {
                                        id: zoomInArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            viewAnim.stop()
                                            camera.z = Math.max(100, camera.z - 80)
                                            modelContainer.updateTagPositions()
                                        }
                                    }
                                    ToolTip.visible: zoomInArea.containsMouse
                                    ToolTip.text: "放大"
                                }

                                Rectangle {
                                    width: 1
                                    Layout.preferredHeight: 10
                                    color: root.curTheme.dividerColor
                                }

                                // － 缩小
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusPill
                                        color: zoomOutArea.containsMouse ? (root.curTheme.isDark ? "#25ffffff" : "#18000000") : "transparent"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "－"
                                        font.pixelSize: 12
                                        color: root.curTheme.textPrimary
                                    }
                                    MouseArea {
                                        id: zoomOutArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            viewAnim.stop()
                                            camera.z = Math.min(2000, camera.z + 80)
                                            modelContainer.updateTagPositions()
                                        }
                                    }
                                    ToolTip.visible: zoomOutArea.containsMouse
                                    ToolTip.text: "缩小"
                                }
                            }
                        }

                        Rectangle { width: 1; height: 12; color: root.curTheme.dividerColor }

                        // 5. 黑白主题切换图标
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: themeMouse.containsMouse ? (root.curTheme.isDark ? "#20ffffff" : "#15000000") : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: root.curTheme.isDark ? "🌙" : "☀️"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: themeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sceneStyle = (root.sceneStyle === 0 ? 1 : 0)
                            }
                            ToolTip.visible: themeMouse.containsMouse
                            ToolTip.text: root.curTheme.isDark ? "当前: 极夜黑 (点击切换为工业白)" : "当前: 工业白 (点击切换为极夜黑)"
                        }

                        Rectangle { width: 1; height: 12; color: root.curTheme.dividerColor }

                        // 6. 一键复位按钮
                        Rectangle {
                            implicitWidth: 52
                            implicitHeight: 24
                            radius: Theme.radiusPill
                            color: resetMouse.containsMouse ? (root.curTheme.isDark ? "#300091ff" : "#0284c7") : (root.curTheme.isDark ? "#1a0284c7" : "#0ea5e9")
                            border.width: 1
                            border.color: root.curTheme.accent
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    text: "↺"
                                    font.pixelSize: 10
                                    color: "#ffffff"
                                }
                                Text {
                                    text: "复位"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }
                            MouseArea {
                                id: resetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelContainer.animateToView(88, 0, 600)
                            }
                            ToolTip.visible: resetMouse.containsMouse
                            ToolTip.text: "恢复默认视角与平移中心"
                        }
                    }
                }

                // 左下角：3D 坐标系小罗盘 (XYZ Axes Gizmo)
                Rectangle {
                    id: gizmoBox
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    width: 60
                    height: 60
                    radius: 30
                    color: root.curTheme.cardBg
                    border.color: root.curTheme.cardBorder
                    border.width: 1

                    Canvas {
                        id: gizmoCanvas
                        anchors.fill: parent
                        property real pitch: modelPivot.pitch
                        property real yaw: modelPivot.yaw

                        Connections {
                            target: root
                            function onSceneStyleChanged() { gizmoCanvas.requestPaint() }
                        }

                        onPitchChanged: requestPaint()
                        onYawChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var cx = width / 2
                            var cy = height / 2
                            var radPitch = pitch * Math.PI / 180
                            var radYaw = yaw * Math.PI / 180

                            // 简易 3D 轴向正交投影
                            function project(x, y, z) {
                                // 绕 Y 轴旋转 (Yaw)
                                var x1 = x * Math.cos(radYaw) - z * Math.sin(radYaw)
                                var z1 = x * Math.sin(radYaw) + z * Math.cos(radYaw)
                                // 绕 X 轴旋转 (Pitch)
                                var y2 = y * Math.cos(radPitch) - z1 * Math.sin(radPitch)
                                return { x: cx + x1 * 20, y: cy - y2 * 20 }
                            }

                            var origin = { x: cx, y: cy }
                            var xEnd = project(1, 0, 0)
                            var yEnd = project(0, 1, 0)
                            var zEnd = project(0, 0, 1)

                            // 绘制 X (红)
                            ctx.lineWidth = 2
                            ctx.strokeStyle = "#f43f5e"
                            ctx.beginPath(); ctx.moveTo(origin.x, origin.y); ctx.lineTo(xEnd.x, xEnd.y); ctx.stroke()

                            // 绘制 Y (绿)
                            ctx.strokeStyle = "#10b981"
                            ctx.beginPath(); ctx.moveTo(origin.x, origin.y); ctx.lineTo(yEnd.x, yEnd.y); ctx.stroke()

                            // 绘制 Z (蓝)
                            ctx.strokeStyle = root.curTheme.accent
                            ctx.beginPath(); ctx.moveTo(origin.x, origin.y); ctx.lineTo(zEnd.x, zEnd.y); ctx.stroke()

                            // 轴端点文本
                            ctx.font = "bold 9px monospace"
                            ctx.fillStyle = "#f43f5e"; ctx.fillText("X", xEnd.x - 3, xEnd.y - 2)
                            ctx.fillStyle = "#10b981"; ctx.fillText("Y", yEnd.x - 3, yEnd.y - 2)
                            ctx.fillStyle = root.curTheme.accent; ctx.fillText("Z", zEnd.x - 3, zEnd.y - 2)
                        }
                    }
                }

                // 底部左侧：内部视觉硬件图例芯片
                Rectangle {
                    anchors.left: gizmoBox.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    anchors.leftMargin: 10
                    radius: Theme.radiusPill
                    color: root.curTheme.cardBg
                    border.color: root.curTheme.cardBorder
                    border.width: 1
                    implicitHeight: 30
                    implicitWidth: legendRow.implicitWidth + 24

                    RowLayout {
                        id: legendRow
                        anchors.centerIn: parent
                        spacing: 12

                        // 相机
                        RowLayout {
                            spacing: 5
                            Rectangle { width: 9; height: 9; radius: 2; color: "#e11d48" }
                            Label {
                                text: "12MP工业相机 (品红标)"
                                color: root.curTheme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeTiny
                                font.bold: true
                            }
                        }

                        // 驱动轮
                        RowLayout {
                            spacing: 5
                            Rectangle { width: 9; height: 9; radius: 4.5; color: root.curTheme.isDark ? "#60a5fa" : "#2563eb"; border.width: 1; border.color: root.curTheme.isDark ? "#ffffff" : "#e2e8f0" }
                            Label {
                                text: "驱动轮1~8 (蓝轮/蓝标)"
                                color: root.curTheme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeTiny
                                font.bold: true
                            }
                        }

                        // 走行轮
                        RowLayout {
                            spacing: 5
                            Rectangle { width: 9; height: 9; radius: 4.5; color: root.curTheme.isDark ? "#fbbf24" : "#d97706"; border.width: 1; border.color: root.curTheme.isDark ? "#ffffff" : "#e2e8f0" }
                            Label {
                                text: "走行轮1~8 (灰轮/琥珀标)"
                                color: root.curTheme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeTiny
                                font.bold: true
                            }
                        }

                        // 光源
                        RowLayout {
                            spacing: 5
                            Rectangle { width: 14; height: 8; radius: 2; color: "#ffffff"; border.width: 1; border.color: root.curTheme.isDark ? "#38bdf8" : "#94a3b8" }
                            Label {
                                text: "条形/面阵光源 (自发光白)"
                                color: root.curTheme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeTiny
                            }
                        }
                    }
                }

                // 右下角：交互操作指引芯片
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    radius: Theme.radiusPill
                    color: root.curTheme.cardBg
                    border.color: root.curTheme.cardBorder
                    border.width: 1
                    implicitWidth: hintLabel.implicitWidth + 20
                    implicitHeight: 28

                    Label {
                        id: hintLabel
                        anchors.centerIn: parent
                        text: "🖱 左键旋转 ╎ 右键/中键拖动平移 ╎ 滚轮缩放 ╎ 顶部预设"
                        color: root.curTheme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeTiny
                    }
                }
            }
        }
    }
}
