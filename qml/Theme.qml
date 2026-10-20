pragma Singleton
import QtQuick 2.15

// 全局视觉令牌。取值与 VisionStudio 的 AppTheme 保持同一套体系（表面层级、四级文字、
// 强调色与状态色），亮色和暗色两套必须同时成立。QML 中不得硬编码颜色、字号和字重，
// 规则见仓库根目录 AGENTS.md。
QtObject {
    id: theme

    // =========================================================================
    // 0. 主题模式
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
    // 1. 表面层级（明度逐级抬高，层级靠明度和留白表达，不靠层层描边）
    // =========================================================================
    readonly property color canvas: isDark ? "#08090c" : "#f1f4f8"          // 最底层画布、空图像区
    readonly property color window: isDark ? "#0b0d11" : "#edf1f6"          // 主窗口底色
    readonly property color surface: isDark ? "#13161c" : "#ffffff"         // 常规面板：顶栏、导航、卡片、状态栏
    readonly property color surfaceAlt: isDark ? "#171b22" : "#f8fafc"      // 交替面板、表格斑马纹、面板内分组
    readonly property color surfaceRaised: isDark ? "#1c2029" : "#ffffff"   // 抬起的卡片容器
    readonly property color surfaceFloating: isDark ? "#272c37" : "#ffffff" // 弹出层、菜单、对话框
    readonly property color fieldFill: isDark ? "#0f1217" : "#ffffff"       // 输入框、下拉框底色
    // 图像区：有图像时两种主题都用深色，判读不受界面主题影响
    readonly property color imageStage: isDark ? "#08090c" : "#14171d"

    // 交互状态：中性灰阶，不带强调色；强调色只留给选中态 activeSubtle
    readonly property color hover: isDark ? "#1b212b" : "#f1f5f9"
    readonly property color pressed: isDark ? "#222a36" : "#e2e8f0"
    readonly property color activeSubtle: isDark ? Qt.rgba(0.30, 0.79, 0.90, 0.12) : Qt.rgba(0.01, 0.41, 0.63, 0.08)

    // 边框层级
    readonly property color borderStrong: isDark ? "#3a4456" : "#94a3b8"    // 悬停描边（中性）
    readonly property color border: isDark ? "#2c3442" : "#cbd5e1"          // 输入框、交互控件外框
    readonly property color borderMuted: isDark ? "#222834" : "#e2e8f0"     // 卡片边框、分割线
    readonly property color selectedBorder: isDark ? Qt.rgba(0.30, 0.79, 0.90, 0.90) : Qt.rgba(0.01, 0.41, 0.63, 0.85) // 选中、焦点
    readonly property color subtleFill: isDark ? Qt.rgba(1.0, 1.0, 1.0, 0.03) : Qt.rgba(0.0, 0.0, 0.0, 0.025) // 表格斑马纹
    readonly property color overlayFill: isDark ? Qt.rgba(0.075, 0.086, 0.11, 0.85) : Qt.rgba(1.0, 1.0, 1.0, 0.92) // 压在图像上的标签底
    readonly property color imageScrim: Qt.rgba(0.0, 0.0, 0.0, 0.45) // 图像上的深色遮罩（两种主题相同）
    readonly property color dialogOverlay: isDark ? Qt.rgba(0.04, 0.05, 0.07, 0.65) : Qt.rgba(0.06, 0.09, 0.13, 0.45)

    // =========================================================================
    // 2. 文字（四级中性色，相邻两级对比度相差 1.5 倍以上）
    // =========================================================================
    readonly property color text: isDark ? "#eef1f5" : "#0f172a"            // 主文本：数值、标题、输入值
    readonly property color textSoft: isDark ? "#b8c1cd" : "#334155"        // 次级：标签名、描述、次要按钮
    readonly property color muted: isDark ? "#8793a3" : "#5b6778"           // 弱化：单位、时间戳、说明
    readonly property color disabled: isDark ? "#5b6676" : "#9aa5b4"        // 禁用、空值占位
    readonly property color textOnAccent: isDark ? "#06222b" : "#ffffff"    // 强调色和状态色实底上的文字

    // =========================================================================
    // 3. 强调色与状态色
    // =========================================================================
    // accent 只用于当前选中项、页面主操作和焦点环；悬停用中性色。
    readonly property color accent: isDark ? "#4cc9e6" : "#0369a1"
    readonly property color accentPressed: isDark ? "#38b2cf" : "#075985"
    readonly property color accentSoft: isDark ? "#10262e" : "#e0f2fe"

    // 状态色只表达状态，不用于标题、普通标签和装饰描边。
    // danger 只用于 NG、故障报警和不可撤销操作的确认。
    readonly property color ok: isDark ? "#34c38f" : "#047857"
    readonly property color okSoft: isDark ? "#08291d" : "#d1fae5"
    readonly property color okBorder: isDark ? Qt.rgba(0.20, 0.76, 0.56, 0.40) : Qt.rgba(0.02, 0.47, 0.34, 0.30)
    readonly property color warn: isDark ? "#e5a23a" : "#b45309"
    readonly property color warnSoft: isDark ? "#2b1e06" : "#fef3c7"
    readonly property color warnBorder: isDark ? Qt.rgba(0.90, 0.64, 0.23, 0.40) : Qt.rgba(0.71, 0.33, 0.04, 0.30)
    readonly property color danger: isDark ? "#f26d6d" : "#b91c1c"
    readonly property color dangerSoft: isDark ? "#331215" : "#fee2e2"
    readonly property color dangerBorder: isDark ? Qt.rgba(0.95, 0.43, 0.43, 0.40) : Qt.rgba(0.73, 0.11, 0.11, 0.30)

    // 轮类别色：只用于区分驱动轮与走行轮（分组标记、图例、三维标签），不表达状态
    readonly property color driveWheel: isDark ? "#79beff" : "#1d6fc4"
    readonly property color driveWheelSoft: isDark ? Qt.rgba(0.47, 0.75, 1.0, 0.12) : "#e8f1fb"
    readonly property color walkWheel: isDark ? "#f0a46b" : "#b4530f"
    readonly property color walkWheelSoft: isDark ? Qt.rgba(0.94, 0.64, 0.42, 0.12) : "#fcf0e6"

    // 三维孪生视图中的相机标记（紫色，避免与 NG 红色混淆）
    readonly property color cameraMarker: isDark ? "#b79cff" : "#6d4fd1"
    readonly property color cameraMarkerSoft: isDark ? Qt.rgba(0.72, 0.61, 1.0, 0.30) : Qt.rgba(0.43, 0.31, 0.82, 0.25)
    // 三维视图有独立的明暗场景风格，其浮层按场景明暗取中性悬停色，而不是按界面主题
    readonly property color hoverOnDark: Qt.rgba(1.0, 1.0, 1.0, 0.12)
    readonly property color hoverOnLight: Qt.rgba(0.0, 0.0, 0.0, 0.06)

    // =========================================================================
    // 4. 文字排版（5 级字号、3 档字重）
    // =========================================================================
    readonly property int fontDisplay: 26   // 核心看板数值（当前架号、KPI）
    readonly property int fontTitle: 18     // 页面与分区标题、对话框标题
    readonly property int fontBody: 14      // 正文、输入框、按钮
    readonly property int fontCaption: 12   // 表格内容、辅助说明、标签
    readonly property int fontMicro: 11     // 只用于数字、单位和徽标，不用于中文句子

    // 只有三档字重：页面大标题 Bold，分区标题、按钮和强调项 Medium，其余 Regular
    readonly property int fontRegular: Font.Normal
    readonly property int fontMedium: Font.Medium
    readonly property int fontBold: Font.Bold

    // 字体族：只用 assets/fonts 中随程序分发的字体（启动时由 main.cpp 加载）。
    // 等宽字体只用于路径、文件名、报文和日志；普通数字用 fontSans
    readonly property string fontSans: "Noto Sans SC"
    readonly property string fontMono: "JetBrains Mono"
    // 数字等宽排版（tnum）：表格、计数、时间等需要对齐的数字用 fontSans 加此特性
    readonly property var fontFeaturesTabular: ({ "tnum": 1 })
    // 全大写英文小标签（如 RACK NO.）的字距
    readonly property real letterSpacingWide: 0.4

    // =========================================================================
    // 5. 圆角、间距与动画
    // =========================================================================
    readonly property int radiusMicro: 4    // 徽标、紧凑按钮
    readonly property int radiusSmall: 6    // 按钮、输入框、下拉菜单
    readonly property int radiusMedium: 10  // 数据卡片、工作面板
    readonly property int radiusLarge: 14   // 独立窗口、模态对话框
    readonly property int radiusPill: 999

    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32

    readonly property int animFast: 140
    readonly property int animNormal: 220
    readonly property int animSlow: 320
}
