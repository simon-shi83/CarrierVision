#pragma once

class QQuickWindow;

// 开发调试用的界面截图：设置环境变量 CV_UI_SNAPSHOT_DIR 时，依次切换到每个导航页面
// 并把窗口保存为 PNG，全部完成后退出程序。未设置该变量时不做任何事。
// 可选 CV_UI_SNAPSHOT_SIZE=宽x高（默认 1920x1080）、CV_UI_SNAPSHOT_DELAY_MS=开始截图前的等待毫秒数、
// CV_UI_SNAPSHOT_SETTLE_MS=每页切换后的等待毫秒数（默认 1500）。
// 主题由调用方在加载 QML 前设置。截图模式不参与单实例检查，应在独立目录运行。
namespace UiSnapshot {

bool requested();
void scheduleIfRequested(QQuickWindow *window);

} // namespace UiSnapshot
