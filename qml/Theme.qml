pragma Singleton
import QtQuick 2.15

QtObject {
    id: theme

    // =========================================================================
    // 0. 主题模式开关 (Theme Mode Switch)
    // 工业级双模切换：
    // - 浅色模式 (Light Mode): 满足工厂强光漫反射环境下的极高视认性与通透感
    // - 深色模式 (Dark Mode): 采用深邃冷蓝黑 (Slate 950)，杜绝纯黑刺眼与残影，适合控制室暗光巡检
    // =========================================================================
    property bool isDark: (typeof appController !== "undefined" && appController && appController.isDarkMode) ? appController.isDarkMode() : false

    function toggleTheme() {
        setDark(!isDark)
    }

    function setDark(val) {
        if (isDark === val) return
        isDark = val
        if (typeof appController !== "undefined" && appController && appController.setDarkMode) {
            appController.setDarkMode(val)
        }
    }

    // =========================================================================
    // 1. 表面高度与物理层次系统 (Surface Hierarchy & Elevation)
    // 遵循 Red Dot 纯粹主义理念，通过精密微明度差构建 4 级空间物理景深
    // =========================================================================
    readonly property color bgApp: isDark ? "#080d14" : "#f1f5f9"           // Level 0: 系统最底层视窗画布 (深海极夜冷黑 / Slate 100)
    readonly property color bgHeader: isDark ? "#0b121c" : "#ffffff"        // Level 1: 顶栏表面 (保持与工作台分界)
    readonly property color bgNav: isDark ? "#0e1622" : "#ffffff"           // Level 1: 水平/垂直导航栏表面
    readonly property color bgStatusBar: isDark ? "#090e16" : "#ffffff"     // Level 1: 底部状态栏表面
    readonly property color bgCard: isDark ? "#101926" : "#ffffff"          // Level 1: 一级工作台卡片/主数据视窗
    readonly property color bgCardElevated: isDark ? "#162233" : "#f8fafc"  // Level 2: 二级悬浮面板/KPI指标容器/列表选中项
    readonly property color bgCardActive: isDark ? "#1d2d42" : "#e2e8f0"    // Level 3: 三级激活/高亮/微交互按下表面
    readonly property color bgInput: isDark ? "#0d1522" : "#ffffff"         // 数据录入框/下拉列表静态背景
    readonly property color bgInputHover: isDark ? "#141f2e" : "#f8fafc"    // 数据录入框悬停背景
    readonly property color bgPopup: isDark ? "#131e2e" : "#ffffff"         // 浮动菜单/气泡提示/下拉面板背景
    readonly property color bgOverlay: isDark ? "#cc05080f" : "#660f172a"   // 模态对话框遮罩层 (亚克力毛玻璃深度遮罩)

    // =========================================================================
    // 2. 精密物理微边框与分割体系 (Borders & Dividers)
    // 采用 1px 精密结构线替代粗重黑框，营造德国工业仪表的严谨与精致
    // =========================================================================
    readonly property color borderSubtle: isDark ? "#1a2636" : "#e2e8f0"     // 微妙基础结构线 (卡片/面板边框/分割线)
    readonly property color borderMedium: isDark ? "#223348" : "#cbd5e1"     // 中等对比度边框 (输入控件/交互组件外框)
    readonly property color borderStrong: isDark ? "#334a66" : "#94a3b8"     // 强调结构边框 (聚焦/选中容器外框)
    readonly property color borderHighlight: isDark ? "#0091ff" : "#0284c7"  // 科技蓝高亮边框 (焦点状态 Focus Ring)
    readonly property color borderHover: isDark ? "#38bdf8" : "#0ea5e9"      // 鼠标悬停边框动效
    readonly property color divider: isDark ? "#162232" : "#e2e8f0"          // 区块分割线颜色

    // =========================================================================
    // 3. 核心科技语义色系 (Semantic Brand & Accents)
    // =========================================================================
    readonly property color primary: isDark ? "#0091ff" : "#0284c7"         // 核心主色蓝 (Primary Sky/Tech Blue)
    readonly property color primaryLight: isDark ? "#38bdf8" : "#0284c7"    // 亮蓝 (文字/图标主强调)
    readonly property color primaryDark: isDark ? "#0066b3" : "#0369a1"     // 深蓝 (主按钮按下态)
    readonly property color primaryGlow: isDark ? "#260091ff" : "#1a0284c7" // 蓝光阴影/呼吸光晕

    // =========================================================================
    // 4. 工业检测状态与机能色 (Metrology Status & Functional Channels)
    // 严格遵照工业三元组规范：[核心识别色] + [浅底光晕 Bg] + [柔和界限 Border]
    // =========================================================================
    // 4.1 OK 正常合格 (Emerald 翡翠翠绿)
    readonly property color ok: isDark ? "#10b981" : "#059669"
    readonly property color okLight: isDark ? "#34d399" : "#059669"
    readonly property color accentSuccess: okLight
    readonly property color okBg: isDark ? "#1810b981" : "#ecfdf5"
    readonly property color okBorder: isDark ? "#4010b981" : "#a7f3d0"

    // 4.2 NG 异常超差 (Crimson / Rose 工业品红) - 警示穿透力强且无刺眼眩光
    readonly property color ng: isDark ? "#f43f5e" : "#e11d48"
    readonly property color ngLight: isDark ? "#fb7185" : "#e11d48"
    readonly property color ngBg: isDark ? "#18f43f5e" : "#fff1f2"
    readonly property color ngBorder: isDark ? "#40f43f5e" : "#fecdd3"

    // 4.3 Warning 预警/趋限 (Amber 琥珀金)
    readonly property color warning: isDark ? "#f59e0b" : "#d97706"
    readonly property color warningLight: isDark ? "#fbbf24" : "#d97706"
    readonly property color warningBg: isDark ? "#18f59e0b" : "#fffbeb"
    readonly property color warningBorder: isDark ? "#40f59e0b" : "#fde68a"

    // 4.4 工业机能硬件通道色 (Functional Equipment Channels)
    // 驱动轮通道 (Drive Wheel - 电光天蓝)
    readonly property color driveWheel: isDark ? "#0ea5e9" : "#0284c7"
    readonly property color driveWheelLight: isDark ? "#38bdf8" : "#0284c7"
    readonly property color driveWheelBg: isDark ? "#180ea5e9" : "#f0f9ff"
    readonly property color driveWheelBorder: isDark ? "#400ea5e9" : "#bae6fd"

    // 走行轮通道 (Walking Wheel - 工业机能亮橙)
    readonly property color walkWheel: isDark ? "#f97316" : "#ea580c"
    readonly property color walkWheelLight: isDark ? "#fb923c" : "#ea580c"
    readonly property color walkWheelBg: isDark ? "#18f97316" : "#fff7ed"
    readonly property color walkWheelBorder: isDark ? "#40f97316" : "#fed7aa"

    // 齿轨轮通道 (Rack Wheel - 高精紫蓝)
    readonly property color rackWheel: isDark ? "#8b5cf6" : "#7c3aed"
    readonly property color rackWheelLight: isDark ? "#a78bfa" : "#7c3aed"
    readonly property color rackWheelBg: isDark ? "#188b5cf6" : "#f5f3ff"
    readonly property color rackWheelBorder: isDark ? "#408b5cf6" : "#ddd6fe"

    // =========================================================================
    // 5. 文本色彩与对比度梯度 (Typography Contrast & Hierarchy)
    // 满足 WCAG 2.1 AAA 级对比度 (textPrimary > 12:1, textSecondary > 7:1)
    // =========================================================================
    readonly property color textPrimary: isDark ? "#f8fafc" : "#0f172a"     // 一级主文本 (Slate 50 / Slate 900)
    readonly property color textSecondary: isDark ? "#94a3b8" : "#475569"   // 二级标签与次要说明 (Slate 400 / Slate 600)
    readonly property color textMuted: isDark ? "#64748b" : "#64748b"       // 三级弱化说明/单位标记/占位符 (Slate 500)
    readonly property color textDisabled: isDark ? "#334155" : "#94a3b8"    // 禁用态文本 (Slate 700 / Slate 400)
    readonly property color textInverse: isDark ? "#080d14" : "#ffffff"     // 反色文本 (深底反白 / 主色按钮文本)
    readonly property color textAccent: isDark ? "#38bdf8" : "#0284c7"      // 链接与重点点缀色

    // =========================================================================
    // 6. 交互状态反馈 Token (Interaction State Tokens)
    // =========================================================================
    readonly property color stateHover: isDark ? "#14ffffff" : "#0a000000"    // 控件悬停微浅层
    readonly property color statePressed: isDark ? "#24ffffff" : "#14000000"  // 控件按下深层
    readonly property color stateFocus: isDark ? "#400091ff" : "#330284c7"   // 聚焦高光微光晕

    // =========================================================================
    // 7. 文字层级体系 (Typography Hierarchy - Red Dot Standard)
    // 包含 8 级模块化字阶、跨平台等宽与无衬线字体栈、标准字重、字距
    // =========================================================================
    // 7.1 字体族栈
    readonly property string fontFamily: "\"Inter\", -apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Segoe UI\", \"Microsoft YaHei\", sans-serif"
    readonly property string fontMono: "\"JetBrains Mono\", \"Fira Code\", \"SF Mono\", Consolas, monospace"

    // 7.2 模块化字阶体系 (Modular Type Scale)
    readonly property int fontDisplayLarge: 32         // 32px: 核心特级工业看板数据/全厂总指标
    readonly property int fontDisplayMedium: 26        // 26px: 一级工业遥测指标数值 / 当前架号 (RACK NO.)
    readonly property int fontDisplaySmall: 20         // 20px: 二级指标数值 / 模块核心数字
    readonly property int fontH1: 20                   // 20px: 页面一级标题 / 主视窗顶部标题
    readonly property int fontH2: 16                   // 16px: 模块二级标题 / 面板头部
    readonly property int fontH3: 14                   // 14px: 卡片分组小标题 / 表格表头 Header
    readonly property int fontBodyLarge: 14            // 14px: 重点正文 / 主要交互按钮字号
    readonly property int fontBody: 13                 // 13px: 基础正文 / 列表项文本 / 录入框内容
    readonly property int fontCaption: 11              // 11px: 辅助说明 / 状态药丸标签 / 时间戳
    readonly property int fontMicro: 9                 // 9px:  极小工业标签 (如 RUNNING, RACK NO.) / 坐标角标

    // 7.3 字重规范 (Font Weights)
    readonly property int weightLight: Font.Light          // 300
    readonly property int weightNormal: Font.Normal        // 400: 标准正文
    readonly property int weightMedium: Font.Medium        // 500: 表头、交互标签
    readonly property int weightSemiBold: Font.DemiBold    // 600: 模块标题、KPI指标数值
    readonly property int weightBold: Font.Bold            // 700: 大看板数值、窗口主标题

    // 7.4 字符间距规范 (Letter Spacing)
    readonly property real letterSpacingTight: -0.3       // 紧凑大数字
    readonly property real letterSpacingNormal: 0.0       // 默认正文
    readonly property real letterSpacingWide: 0.4         // 标签微间距
    readonly property real letterSpacingLoose: 0.8        // 工业全大写英文标签专用微间距

    // 7.5 向下兼容旧字阶命名 (Backward Compatibility)
    readonly property int fontSizeH1: 20
    readonly property int fontSizeH2: 16
    readonly property int fontSizeH3: 14
    readonly property int fontSizeBody: 13
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeTiny: 9

    // =========================================================================
    // 8. 统一精密圆角规格 (Radii System)
    // =========================================================================
    readonly property int radiusSm: 4                  // 微型标签/徽章/紧凑微按钮
    readonly property int radiusMd: 8                  // 标准按钮/输入框/下拉菜单
    readonly property int radiusLg: 12                 // 核心数据卡片/工作台面板
    readonly property int radiusXl: 16                 // 独立视窗/主模态弹窗
    readonly property int radiusPill: 999              // 胶囊药丸指示器

    // =========================================================================
    // 9. 微动效与过渡时长 (Motion Curves & Transitions)
    // =========================================================================
    readonly property int animFast: 120                // 悬停反馈 / 按下动效
    readonly property int animNormal: 200              // 弹窗展开 / 选项卡切换
    readonly property int animSlow: 350                // 抽屉展开 / 大图入场
}
