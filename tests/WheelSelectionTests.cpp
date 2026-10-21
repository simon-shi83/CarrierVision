#include <QtTest>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QDir>
#include <QTemporaryDir>
#include <QImage>
#include <QFontDatabase>
#include "common/WheelIdentity.h"
#include "app/ImageListModel.h"

// 仅提供映射和隔离测试数据，加载真实查询组件以验证 QML 传参契约。
class IdentityContext final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList gearSumResult MEMBER rows CONSTANT)
    Q_PROPERTY(QObject *searchImagesModel READ searchModel CONSTANT)
    Q_PROPERTY(QString searchSummary MEMBER summary CONSTANT)
public:
    ImageListModel model;
    QString summary;
    QObject *searchModel() { return &model; }
    Q_INVOKABLE int latestRackWheelImageRack() const { return 3; }
    Q_INVOKABLE int latestRackWheelTotalPages(int) const { return 1; }
    Q_INVOKABLE void loadLatestRackWheelImages(int) {}
    Q_INVOKABLE void loadLatestRackWheelImagesPage(int, int) {}
    Q_INVOKABLE QVariantList rackWheelDistances(int) const { return {10, 10, 10, 10, 10, 10, 10, 10}; }
    QVariantList rows{{QVariantMap{{"wheel", 1}, {"ok", 2}, {"ng", 1}}},
                      {QVariantMap{{"wheel", 9}, {"ok", 1}, {"ng", 3}}}};
    Q_INVOKABLE bool isDarkMode() const { return qEnvironmentVariable("CV_UI_SNAPSHOT_THEME") == QStringLiteral("dark"); }
    Q_INVOKABLE QString wheelLabel(const QVariant &raw) const { return WheelIdentity::label(raw); }
    Q_INVOKABLE int wheelRawId(const QVariant &pos) const { return WheelIdentity::rawId(pos); }
    Q_INVOKABLE int wheelPosition(const QVariant &raw) const { return WheelIdentity::position(raw); }
    Q_INVOKABLE QString wheelCsvIdentity(const QVariant &raw) const { return WheelIdentity::csvIdentity(raw); }
signals:
    void slotUpdated(int slot);
    void searchSummaryChanged();
    void latestRackLoadFinished(int count, const QString &dbPath);
};

class WheelSelectionTests final : public QObject
{
    Q_OBJECT
    static QQuickItem *findItem(QQuickItem *root, const QString &name)
    {
        if (root->objectName() == name) return root;
        for (QQuickItem *child : root->childItems())
            if (QQuickItem *found = findItem(child, name)) return found;
        return nullptr;
    }
private slots:
    void querySelectionAndCsvUseOriginalKeys()
    {
        QTest::failOnWarning(QRegularExpression(QStringLiteral(".*")));
        QQmlEngine engine;
        IdentityContext identity;
        engine.rootContext()->setContextProperty(QStringLiteral("appController"), &identity);
        QQmlComponent component(&engine);
        component.setData("import CarrierVisionWheelTests\nQueryConditionBar {}", QUrl());
        QScopedPointer<QObject> bar(component.create());
        QVERIFY2(bar, qPrintable(component.errorString()));
        QQuickWindow window;
        window.resize(1500, 800);
        auto *barItem = qobject_cast<QQuickItem *>(bar.data());
        QVERIFY(barItem);
        barItem->setParentItem(window.contentItem());
        barItem->setWidth(1450);
        window.show();
        QSignalSpy submitted(bar.data(), SIGNAL(searchClicked(QString,QString,int,QString,QString,QString)));
        QVERIFY(submitted.isValid());
        for (int raw : {9, 16, 1, 8, 0}) {
            QVERIFY(QMetaObject::invokeMethod(bar.data(), "applyQuery",
                Q_ARG(QVariant, QStringLiteral("2026-10-01")), Q_ARG(QVariant, QStringLiteral("2026-10-21")),
                Q_ARG(QVariant, raw), Q_ARG(QVariant, QStringLiteral("NG"))));
            QCOMPARE(bar->property("turno").toString(), QString::number(raw));
            QCOMPARE(submitted.last().at(3).toString(), QString::number(raw));
            QCOMPARE(submitted.last().at(4).toString(), QStringLiteral("NG"));
        }
        QObject *selector = bar->findChild<QObject *>(QStringLiteral("wheelSelector"));
        QVERIFY(selector);
        for (const QVariant &invalid : QVariantList{17, -1, 1.5, QStringLiteral("invalid"), QVariant()}) {
            QVERIFY(QMetaObject::invokeMethod(selector, "setSelectionToken", Q_ARG(QVariant, invalid)));
            QCOMPARE(selector->property("selectionToken").toString(), QStringLiteral("0"));
            QCOMPARE(selector->property("displayText").toString(), QStringLiteral("全部轮位"));
        }
        QObject *toggle = selector->findChild<QObject *>(QStringLiteral("wheelSelectorButton"));
        QVERIFY(toggle);
        // 弹窗中每个显示轮位按钮提交一次映射后的原始编号。
        for (int pos = 1; pos <= 16; ++pos) {
            QVERIFY(QMetaObject::invokeMethod(toggle, "clicked"));
            QCoreApplication::processEvents();
            QObject *button = findItem(window.contentItem(), QStringLiteral("wheelPosition%1").arg(pos));
            QVERIFY2(button, qPrintable(QString::number(pos)));
            const QString snapshots = qEnvironmentVariable("CV_WHEEL_TEST_SNAPSHOT_DIR");
            if (pos == 1 && !snapshots.isEmpty()) {
                QDir().mkpath(snapshots);
                QTest::qWait(200);
                QVERIFY(window.grabWindow().save(QDir(snapshots).filePath(QStringLiteral("wheel-selector.png"))));
            }
            QVERIFY(QMetaObject::invokeMethod(button, "clicked"));
            QCOMPARE(selector->property("selectionToken").toInt(), WheelIdentity::rawId(pos));
            QCOMPARE(selector->property("displayText").toString(), WheelIdentity::label(WheelIdentity::rawId(pos)));
        }
        QQmlComponent inspectComponent(&engine);
        inspectComponent.setData("import CarrierVisionWheelTests\nStationImageInspectDialog {}", QUrl());
        QScopedPointer<QObject> inspect(inspectComponent.create());
        QVERIFY2(inspect, qPrintable(inspectComponent.errorString()));
        QObject *metric = inspect->findChild<QObject *>(QStringLiteral("wheelIdentityMetric"));
        QVERIFY(metric);
        QVariantMap inspectItem{{"slot", 9}, {"cameraId", 9}, {"fileName", ""}, {"wheelsInfo", ""}};
        inspect->setProperty("currentItemObject", inspectItem);
        QCOMPARE(metric->property("metricValue").toString(), WheelIdentity::label(QVariant()));
        inspectItem.insert("wheelId", 1);
        inspect->setProperty("currentItemObject", inspectItem);
        QCOMPARE(metric->property("metricValue").toString(), QStringLiteral("轮位9/驱动轮1"));
        // 真实 ImageListModel 把 slot 暴露成相机号：轮2和轮8不能被错放到相机1/6列。
        QTemporaryDir imageDir;
        QVERIFY(imageDir.isValid());
        const QString calibrationPath = imageDir.filePath(QStringLiteral("calibration.png"));
        QImage calibrationImage(32, 32, QImage::Format_RGB32);
        calibrationImage.fill(Qt::blue);
        QVERIFY(calibrationImage.save(calibrationPath));
        QVector<ImageItem> calibrationItems;
        for (int raw : {2, 8, 9}) {
            ImageItem item;
            item.carrierId = 3;
            item.wheelId = raw;
            item.slot = raw;
            item.cameraId = raw == 2 ? 1 : (raw == 8 ? 6 : 7);
            item.distance = 120.0 + raw / 10.0;
            item.filePath = calibrationPath;
            item.fileName = QStringLiteral("raw%1.png").arg(raw);
            calibrationItems.append(item);
        }
        identity.model.setItems(calibrationItems);
        QCOMPARE(identity.model.get(0).value("slot").toInt(), 1);
        QQmlComponent calibrationComponent(&engine);
        calibrationComponent.setData("import CarrierVisionWheelTests\nCalibrationPage {}", QUrl());
        QScopedPointer<QObject> calibration(calibrationComponent.create());
        QVERIFY2(calibration, qPrintable(calibrationComponent.errorString()));
        QVERIFY(QMetaObject::invokeMethod(calibration.data(), "rebuildWheelImages"));
        const QVariantList measured = calibration->property("databaseDistanceValues").toList();
        QCOMPARE(measured.size(), 8);
        QCOMPARE(measured[0].toString(), QStringLiteral("0"));
        QCOMPARE(measured[1].toDouble(), 120.2);
        QCOMPARE(measured[7].toDouble(), 120.8);
        const QVariantList wheelImages = calibration->property("wheelImages").toList();
        QCOMPARE(wheelImages[1].toMap().value("wheelId").toInt(), 2);
        QCOMPARE(wheelImages[7].toMap().value("wheelId").toInt(), 8);
        auto *calibrationRoot = qobject_cast<QQuickItem *>(calibration.data());
        QVERIFY(calibrationRoot);
        calibrationRoot->setParentItem(window.contentItem());
        calibrationRoot->setWidth(1280);
        calibrationRoot->setHeight(800);
        QQuickItem *image = findItem(calibrationRoot, QStringLiteral("calibrationImage2"));
        QVERIFY(image);
        QCOMPARE(image->property("source").toUrl(), QUrl::fromLocalFile(calibrationPath));
        QTRY_COMPARE(image->property("status").toInt(), 1); // Image.Ready：真实文件可解码

        for (const QString &type : {QStringLiteral("WheelQueryBar"), QStringLiteral("DateQueryBar")}) {
            QQmlComponent csvComponent(&engine);
            csvComponent.setData((QStringLiteral("import CarrierVisionWheelTests\n") + type + QStringLiteral(" {}")).toUtf8(), QUrl());
            QScopedPointer<QObject> csvBar(csvComponent.create());
            QVERIFY2(csvBar, qPrintable(csvComponent.errorString()));
            QVariant csv;
            QVERIFY(QMetaObject::invokeMethod(csvBar.data(), "generateCsv", Q_RETURN_ARG(QVariant, csv)));
            QVERIFY(csv.toString().startsWith(QStringLiteral("wheel_id,position_no,wheel_type,type_index,")));
            QVERIFY(csv.toString().contains(QStringLiteral("1,9,drive,1,2,1\n")));
            QVERIFY(csv.toString().contains(QStringLiteral("9,1,walk,1,1,3\n")));
        }
    }
};

int main(int argc, char **argv)
{
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    QGuiApplication app(argc, argv);
    const QDir fonts(qEnvironmentVariable("CV_UI_FONT_DIR"));
    if (!qEnvironmentVariable("CV_UI_FONT_DIR").isEmpty())
        for (const QString &file : fonts.entryList({QStringLiteral("*.otf"), QStringLiteral("*.ttf")}))
            QFontDatabase::addApplicationFont(fonts.filePath(file));
    WheelSelectionTests tests;
    return QTest::qExec(&tests, argc, argv);
}
#include "WheelSelectionTests.moc"
