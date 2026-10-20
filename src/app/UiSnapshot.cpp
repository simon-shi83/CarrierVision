#include "app/UiSnapshot.h"

#include "common/AppLogger.h"

#include <QCoreApplication>
#include <QDir>
#include <QImage>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>

namespace UiSnapshot {

namespace {

constexpr int kSettleMs = 1500;

int settleMs()
{
    const int v = qEnvironmentVariableIntValue("CV_UI_SNAPSHOT_SETTLE_MS");
    return v > 0 ? v : kSettleMs;
}

void capturePage(QQuickWindow *window, QObject *nav, const QVariantList &pages, int index, const QString &dir)
{
    if (index >= pages.size()) {
        LOG_INFO("[UiSnapshot] 截图完成，共 {} 页，目录 {}", pages.size(), dir.toStdString());
        QCoreApplication::exit(0); // quit() 会先关窗口，被主窗口的退出密码确认拦下
        return;
    }
    QMetaObject::invokeMethod(nav, "navigateTo", Q_ARG(QVariant, index), Q_ARG(QVariant, pages.at(index)));
    QTimer::singleShot(settleMs(), window, [window, nav, pages, index, dir]() {
        const QString title = pages.at(index).toMap().value(QStringLiteral("title")).toString();
        const QString path = QDir(dir).filePath(QStringLiteral("%1_%2.png").arg(index, 2, 10, QLatin1Char('0')).arg(title));
        if (!window->grabWindow().save(path))
            LOG_WARN("[UiSnapshot] 保存截图失败: {}", path.toStdString());
        capturePage(window, nav, pages, index + 1, dir);
    });
}

} // namespace

bool requested()
{
    return !qEnvironmentVariable("CV_UI_SNAPSHOT_DIR").trimmed().isEmpty();
}

void scheduleIfRequested(QQuickWindow *window)
{
    if (!window || !requested()) return;
    const QString dir = qEnvironmentVariable("CV_UI_SNAPSHOT_DIR").trimmed();
    QDir().mkpath(dir);

    const QStringList size = qEnvironmentVariable("CV_UI_SNAPSHOT_SIZE", QStringLiteral("1920x1080")).split(u'x');
    if (size.size() == 2 && size.at(0).toInt() > 0 && size.at(1).toInt() > 0) {
        window->showNormal();
        window->resize(size.at(0).toInt(), size.at(1).toInt());
    }

    const int startDelay = qMax(kSettleMs * 2, qEnvironmentVariableIntValue("CV_UI_SNAPSHOT_DELAY_MS"));
    QTimer::singleShot(startDelay, window, [window, dir]() {
        QObject *nav = window->findChild<QObject *>(QStringLiteral("navMenu"));
        if (!nav) {
            LOG_ERROR("[UiSnapshot] 找不到导航菜单 navMenu，取消截图");
            QCoreApplication::exit(1);
            return;
        }
        capturePage(window, nav, nav->property("menuData").toList(), 0, dir);
    });
}

} // namespace UiSnapshot
