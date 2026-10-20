#include <QtTest>
#include <QSqlDatabase>
#include <QSqlQuery>

#include "common/AgcUtils.h"
#include "data/DbSchema.h"
#include "app/ImageListModel.h"
#include "data/StatsService.h"
#include "data/SearchService.h"
#include "data/SettingsStore.h"
#include "ingest/IngestCoordinator.h"
#include "common/StorageMonitor.h"
#include "network/NetworkAccess.h"

#include <QTemporaryDir>
#include <QDir>

class CoreBoundaryTests final : public QObject
{
    Q_OBJECT

private slots:
    void modelRejectsOutOfRangeSlots()
    {
        ImageListModel model;
        ImageItem item;

        QVERIFY(!model.updateSlotItem(-1, item));
        QVERIFY(!model.updateSlotItem(1000, item));
        QCOMPARE(model.count(), 0);

        QVERIFY(model.updateSlotItem(11, item));
        QCOMPARE(model.count(), 12);
    }

    void modelDynamicallyResizes()
    {
        ImageListModel model;
        QVector<ImageItem> valid(12);
        model.setItems(valid);
        QCOMPARE(model.count(), 12);

        QVector<ImageItem> valid16(16);
        model.setItems(valid16);
        QCOMPARE(model.count(), 16);
    }

    void dateParserRejectsInvalidCalendarDates()
    {
        QVERIFY(!AgcUtils::parseFlexibleDateTime(QStringLiteral("2026-02-31"), false).isValid());
        QVERIFY(!AgcUtils::parseFlexibleDateTime(QStringLiteral("not-a-date"), false).isValid());
        QVERIFY(AgcUtils::parseFlexibleDateTime(QStringLiteral("2024-02-29"), false).isValid());
    }

    void alertRecordLifecycleFollowsLatestTimestamp()
    {
        const QString connectionName = QStringLiteral("TestBoundaryDb");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(QStringLiteral(":memory:"));
            QVERIFY(db.open());
            QVERIFY(DBSchema::ensureAllTables(db));

            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) "
                "VALUES(:time,1,1,1,:result,:image)"));
            auto addRecord = [&insert](const QString &time, int result, const QString &image) {
                insert.bindValue(QStringLiteral(":time"), time);
                insert.bindValue(QStringLiteral(":result"), result);
                insert.bindValue(QStringLiteral(":image"), image);
                return insert.exec();
            };

            QVERIFY(addRecord(QStringLiteral("2026-09-04T10:00:00"), 0, QStringLiteral("new-ng.jpg")));
            QVERIFY(addRecord(QStringLiteral("2026-09-04T09:00:00"), 0, QStringLiteral("old-ng.jpg")));

            QSqlQuery alert(db);
            QVERIFY(alert.exec(QStringLiteral("SELECT imagename FROM alertrecord WHERE carrier_id=1 AND wheel_id=1")));
            QVERIFY(alert.next());
            QCOMPARE(alert.value(0).toString(), QStringLiteral("new-ng.jpg"));

            // 迟到的旧 OK 不能清除更新的 NG；更新的 OK 才能清除。
            QVERIFY(addRecord(QStringLiteral("2026-09-04T09:30:00"), 1, QStringLiteral("old-ok.jpg")));
            QVERIFY(alert.exec(QStringLiteral("SELECT COUNT(*) FROM alertrecord")));
            QVERIFY(alert.next());
            QCOMPARE(alert.value(0).toInt(), 1);

            QVERIFY(addRecord(QStringLiteral("2026-09-04T11:00:00"), 1, QStringLiteral("new-ok.jpg")));
            QVERIFY(alert.exec(QStringLiteral("SELECT COUNT(*) FROM alertrecord")));
            QVERIFY(alert.next());
            QCOMPARE(alert.value(0).toInt(), 0);
            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }
    void statsServiceAggregatesByWheelGroupAndRack()
    {
        const QString connectionName = QStringLiteral("TestStatsDb");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(QStringLiteral(":memory:"));
            QVERIFY(db.open());
            QVERIFY(DBSchema::ensureAllTables(db));

            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) "
                "VALUES(:time,:rack,1,:wheel,:result,:image)"));
            int serial = 0;
            auto add = [&](const QString &time, int rack, int wheel, int result) {
                insert.bindValue(QStringLiteral(":time"), time);
                insert.bindValue(QStringLiteral(":rack"), rack);
                insert.bindValue(QStringLiteral(":wheel"), wheel);
                insert.bindValue(QStringLiteral(":result"), result);
                insert.bindValue(QStringLiteral(":image"), QStringLiteral("img%1.jpg").arg(++serial));
                return insert.exec();
            };
            QVERIFY(add(QStringLiteral("2026-09-04 10:00:00"), 3, 1, 1));
            QVERIFY(add(QStringLiteral("2026-09-04 10:00:01"), 3, 2, 0));
            QVERIFY(add(QStringLiteral("2026-09-04 10:00:02"), 3, 10, 0));
            QVERIFY(add(QStringLiteral("2026-09-04 10:00:03"), 5, 1, 0));
            QVERIFY(add(QStringLiteral("2026-09-06 10:00:00"), 3, 1, 0)); // 时间范围外

            const QString start = QStringLiteral("2026-09-04");
            const QString end = QStringLiteral("2026-09-05");

            const QVariantList drive = StatsService::wheelGroupRackStats(db, start, end, 1, 8);
            QCOMPARE(drive.size(), 50);
            QCOMPARE(drive.at(2).toMap().value("ok").toLongLong(), 1);
            QCOMPARE(drive.at(2).toMap().value("ng").toLongLong(), 1);
            QCOMPARE(drive.at(2).toMap().value("loss").toDouble(), 50.0);
            QCOMPARE(drive.at(4).toMap().value("ng").toLongLong(), 1);

            const QVariantList walk = StatsService::wheelGroupRackStats(db, start, end, 9, 16);
            QCOMPARE(walk.at(2).toMap().value("ng").toLongLong(), 1);
            QCOMPARE(walk.at(2).toMap().value("ok").toLongLong(), 0);

            const QVariantList byRack = StatsService::wheelRackResultStats(db, start, end, 1, QStringLiteral("NG"));
            QCOMPARE(byRack.at(4).toMap().value("count").toInt(), 1);
            QCOMPARE(byRack.at(4).toMap().value("percent").toDouble(), 100.0);

            const QVariantList walkSlots = StatsService::rackWheelResultStats(db, start, end, 3, QStringLiteral("NG"), 1);
            QCOMPARE(walkSlots.size(), 8);
            QCOMPARE(walkSlots.at(1).toMap().value("wheel").toInt(), 10);
            QCOMPARE(walkSlots.at(1).toMap().value("count").toInt(), 1);

            const QVariantList photos = StatsService::rackPhotoCounts(db);
            QCOMPARE(photos.at(2).toMap().value("count").toInt(), 2);

            // 未指定架号时取最新入库记录的架号
            const QVariantMap overview = StatsService::homepageCurrentDetection(db, 0);
            QCOMPARE(overview.value("rack").toInt(), 3);
            QCOMPARE(overview.value("totalCount").toInt(), 4);
            QCOMPARE(overview.value("ngCount").toInt(), 3);
            QCOMPARE(overview.value("drive").toList().size(), 8);

            // 轮系汇总：默认输出 1~8；连续 8 个轮号时输出该范围；按架号过滤
            const QVariantList gear = StatsService::gearSum(db, start, end, QString(), {});
            QCOMPARE(gear.size(), 8);
            QCOMPARE(gear.at(0).toMap().value("ok").toInt(), 1);
            QCOMPARE(gear.at(0).toMap().value("ng").toInt(), 1);
            QCOMPARE(gear.at(1).toMap().value("ng").toInt(), 1);
            const QVariantList walkGear = StatsService::gearSum(db, start, end, QString(), {9, 10, 11, 12, 13, 14, 15, 16});
            QCOMPARE(walkGear.at(1).toMap().value("wheel").toInt(), 10);
            QCOMPARE(walkGear.at(1).toMap().value("ng").toInt(), 1);
            const QVariantList rackGear = StatsService::gearSum(db, start, end, QStringLiteral("3"), {});
            QCOMPARE(rackGear.at(0).toMap().value("ok").toInt(), 1);
            QCOMPARE(rackGear.at(0).toMap().value("ng").toInt(), 0);

            bool known = true;
            StatsService::run(db, QStringLiteral("noSuchStats"), {}, &known);
            QVERIFY(!known);
            StatsService::run(db, QStringLiteral("driveWheelRackStats"), {start}, &known);
            QVERIFY(!known);
            const QVariant viaRun = StatsService::run(db, QStringLiteral("driveWheelRackStats"), {start, end}, &known);
            QVERIFY(known);
            QCOMPARE(viaRun.toList(), drive);
            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }
    void searchServiceFiltersAndPagesRecords()
    {
        const QString connectionName = QStringLiteral("TestSearchDb");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(QStringLiteral(":memory:"));
            QVERIFY(db.open());
            QVERIFY(DBSchema::ensureAllTables(db));

            QTemporaryDir archive;
            QVERIFY(archive.isValid());
            QFile present(archive.filePath(QStringLiteral("present.png")));
            QVERIFY(present.open(QIODevice::WriteOnly));
            present.close();

            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) "
                "VALUES(:time,:rack,1,:wheel,:result,:image)"));
            // 架 2 的 16 个轮各一条，轮 5 为 NG；第 1 条使用存在的图片
            for (int wheel = 1; wheel <= 16; ++wheel) {
                insert.bindValue(QStringLiteral(":time"), QStringLiteral("2026-09-04 10:00:%1").arg(wheel, 2, 10, QLatin1Char('0')));
                insert.bindValue(QStringLiteral(":rack"), 2);
                insert.bindValue(QStringLiteral(":wheel"), wheel);
                insert.bindValue(QStringLiteral(":result"), wheel == 5 ? 0 : 1);
                insert.bindValue(QStringLiteral(":image"), wheel == 1 ? QStringLiteral("present.png")
                                                                      : QStringLiteral("missing_%1.png").arg(wheel));
                QVERIFY(insert.exec());
            }

            auto count = [&](const SearchService::RecordFilter &filter) {
                int total = -1;
                QVector<ImageItem> items;
                if (!SearchService::queryRecordPage(db, QStringLiteral("record"), filter, 1, 50,
                                                    archive.path(), QString(), total, items))
                    return -1;
                return total;
            };
            const QString start = QStringLiteral("2026-09-04");
            const QString end = QStringLiteral("2026-09-04");
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QString())), 16);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QStringLiteral("DRIVE"))), 8);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QStringLiteral("WALK"))), 8);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QStringLiteral("1, 3,99"))), 2);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QStringLiteral("7"))), 1);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 0, QStringLiteral("17"))), 0);
            QCOMPARE(count(SearchService::buildRecordFilter(start, end, 3, QString())), 0);
            QCOMPARE(count(SearchService::buildRecordFilter(QStringLiteral("2026-09-05"), QString(), 0, QString())), 0);

            int result = -1;
            QVERIFY(SearchService::parseResultFilter(QStringLiteral(" ng "), result));
            QCOMPARE(result, 0);
            QVERIFY(!SearchService::parseResultFilter(QStringLiteral("ALL"), result));
            SearchService::RecordFilter ngOnly = SearchService::buildRecordFilter(start, end, 2, QString());
            ngOnly.where << QStringLiteral("result = :res");
            ngOnly.binds.append({QStringLiteral(":res"), 0});
            QCOMPARE(count(ngOnly), 1);

            // 分页按时间倒序，第 2 页（每页 5 条）从轮 11 开始
            int total = 0;
            QVector<ImageItem> page;
            QVERIFY(SearchService::queryRecordPage(db, QStringLiteral("record"),
                SearchService::buildRecordFilter(start, end, 0, QString()), 2, 5,
                archive.path(), QString(), total, page));
            QCOMPARE(total, 16);
            QCOMPARE(page.size(), 5);
            QCOMPARE(page.first().wheelId, 11);
            QCOMPARE(page.last().wheelId, 7);

            // 只有存在的图片才得到路径
            page.clear();
            QVERIFY(SearchService::queryRecordPage(db, QStringLiteral("record"),
                SearchService::buildRecordFilter(start, end, 0, QStringLiteral("1,2")), 1, 10,
                archive.path(), QString(), total, page));
            QCOMPARE(page.size(), 2);
            QCOMPARE(page.at(1).wheelId, 1);
            QCOMPARE(page.at(1).filePath, QFileInfo(present).absoluteFilePath());
            QVERIFY(page.at(0).filePath.isEmpty());
            QCOMPARE(page.at(0).fileName, QStringLiteral("missing_2.png"));
            QVERIFY(SearchService::resolveImagePath(QStringLiteral("images/present.png"), archive.path(), QString()).endsWith(QStringLiteral("present.png")));
            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }
    void settingsStoreRoundTripsAndValidates()
    {
        const QString connectionName = QStringLiteral("TestSettingsDb");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(QStringLiteral(":memory:"));
            QVERIFY(db.open());
            QVERIFY(DBSchema::ensureAllTables(db));

            // 默认配置：建表时写入 agc 账户、端口 21、槽位 1:1
            SettingsStore::FtpSettings loaded = SettingsStore::loadFtpSettings(db, 2121);
            QCOMPARE(loaded.port, 21);
            QVERIFY(loaded.users.contains(QStringLiteral("agc")));
            QCOMPARE(loaded.slotMapping, SettingsStore::defaultSlotMapping());

            SettingsStore::FtpSettings changed = loaded;
            changed.port = 2222;
            changed.root = QStringLiteral("/data/upload");
            changed.users = {{QStringLiteral("cam1"), AgcUtils::encodePassword(QStringLiteral("pw"))}};
            changed.slotMapping[0] = 14;
            QString error;
            QVERIFY(SettingsStore::saveFtpSettings(db, changed, error));
            loaded = SettingsStore::loadFtpSettings(db, 21);
            QCOMPARE(loaded.port, 2222);
            QCOMPARE(loaded.root, QStringLiteral("/data/upload"));
            QCOMPARE(loaded.users.keys(), QStringList{QStringLiteral("cam1")});
            QCOMPARE(loaded.slotMapping.at(0), 14);

            // 越界端口回退到调用方默认值，根目录为文件系统根时清空，历史 archive 目录迁移为 images
            QVERIFY(DBSchema::setConfig(db, QStringLiteral("ftp/port"), QStringLiteral("70000")));
            QVERIFY(DBSchema::setConfig(db, QStringLiteral("ftp/rootDirectory"), QDir::rootPath()));
            loaded = SettingsStore::loadFtpSettings(db, 2121);
            QCOMPARE(loaded.port, 2121);
            QVERIFY(loaded.root.isEmpty());
            QVERIFY(DBSchema::setConfig(db, QStringLiteral("ftp/rootDirectory"), QStringLiteral("archive")));
            SettingsStore::loadFtpSettings(db, 21);
            QCOMPARE(DBSchema::getConfig(db, QStringLiteral("ftp/rootDirectory")), QStringLiteral("images"));

            // 相对路径原样保存，按程序目录（而非工作目录）解析；程序目录内的绝对路径转为相对路径
            QCOMPARE(SettingsStore::loadFtpSettings(db, 21).root, QStringLiteral("images"));
            const QString appDir = QDir::cleanPath(QCoreApplication::applicationDirPath());
            QCOMPARE(AgcUtils::resolveAppPath(QStringLiteral("images")), appDir + QStringLiteral("/images"));
            QCOMPARE(AgcUtils::toAppRelativePath(appDir + QStringLiteral("/images")), QStringLiteral("images"));
            const QString outside = QDir::cleanPath(QDir::tempPath() + QStringLiteral("/cv-upload"));
            QCOMPARE(AgcUtils::toAppRelativePath(outside), outside);
            QCOMPARE(AgcUtils::toAppRelativePath(appDir), appDir);

            // 明文存储的 FTP 账户在加载时升级为哈希，原密码仍可验证
            QSqlQuery plain(db);
            QVERIFY(plain.exec(QStringLiteral("UPDATE ftp_users SET password_hash = 'legacy-pass' WHERE username = 'cam1'")));
            loaded = SettingsStore::loadFtpSettings(db, 21);
            QVERIFY(loaded.users.value(QStringLiteral("cam1")).startsWith(QStringLiteral("sha256$")));
            QVERIFY(AgcUtils::verifyEncodedPassword(QStringLiteral("legacy-pass"), loaded.users.value(QStringLiteral("cam1"))));
            QVERIFY(plain.exec(QStringLiteral("SELECT password_hash FROM ftp_users WHERE username = 'cam1'")) && plain.next());
            QVERIFY(plain.value(0).toString().startsWith(QStringLiteral("sha256$")));

            QVERIFY(DBSchema::setConfig(db, QStringLiteral("security/settingsPassword"), QStringLiteral("plain-admin")));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("plain-admin")));
            QVERIFY(DBSchema::getConfig(db, QStringLiteral("security/settingsPassword")).startsWith(QStringLiteral("sha256$")));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("plain-admin")));

            QVERIFY(SettingsStore::resetSettingsPassword(db));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("123456")));
            QVERIFY(!SettingsStore::changeSettingsPassword(db, QStringLiteral("123456"), QStringLiteral("short")));
            QVERIFY(!SettingsStore::changeSettingsPassword(db, QStringLiteral("wrong"), QStringLiteral("long-enough")));
            QVERIFY(SettingsStore::changeSettingsPassword(db, QStringLiteral("123456"), QStringLiteral("long-enough")));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("long-enough")));
            QVERIFY(!SettingsStore::verifySettingsPassword(db, QStringLiteral("123456")));

            const QVariantList before = SettingsStore::rackWheelDistances(db, 4);
            QCOMPARE(before.size(), 8);
            // 维护口令：默认未设置；设置需当前设置密码；可单独授权重置设置密码
            QVERIFY(!SettingsStore::hasMaintenancePassword(db));
            QVERIFY(!SettingsStore::verifyMaintenancePassword(db, QString()));
            QVERIFY(!SettingsStore::resetSettingsPasswordAuthorized(db, QStringLiteral("wrong")));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("long-enough")));
            QVERIFY(!SettingsStore::setMaintenancePassword(db, QStringLiteral("wrong"), QStringLiteral("maint-code")));
            QVERIFY(!SettingsStore::setMaintenancePassword(db, QStringLiteral("long-enough"), QStringLiteral("short")));
            QVERIFY(!SettingsStore::setMaintenancePassword(db, QStringLiteral("long-enough"), QStringLiteral("long-enough")));
            QVERIFY(SettingsStore::setMaintenancePassword(db, QStringLiteral("long-enough"), QStringLiteral("maint-code")));
            QVERIFY(SettingsStore::hasMaintenancePassword(db));
            QVERIFY(SettingsStore::resetSettingsPasswordAuthorized(db, QStringLiteral("maint-code")));
            QVERIFY(SettingsStore::verifySettingsPassword(db, QStringLiteral("123456")));
            QVERIFY(SettingsStore::resetSettingsPasswordAuthorized(db, QStringLiteral("123456"))); // 当前设置密码同样可授权
            QVERIFY(DBSchema::setConfig(db, QStringLiteral("security/maintenancePassword"), QStringLiteral("plain")));
            QVERIFY(!SettingsStore::verifyMaintenancePassword(db, QStringLiteral("plain"))); // 明文维护口令不被接受

            QVERIFY(!SettingsStore::saveRackWheelDistances(db, 51, {QStringLiteral("1")}));
            QVERIFY(!SettingsStore::saveRackWheelDistances(db, 4, {QStringLiteral("1"), QStringLiteral("-2")}));
            QVERIFY(!SettingsStore::saveRackWheelDistances(db, 4, {QStringLiteral("abc")}));
            QCOMPARE(SettingsStore::rackWheelDistances(db, 4), before); // 校验失败时不写入任何一项
            QVERIFY(SettingsStore::saveRackWheelDistances(db, 4, {QStringLiteral("120.5"), QStringLiteral("119")}));
            const QVariantList distances = SettingsStore::rackWheelDistances(db, 4);
            QCOMPARE(distances.size(), 8);
            QCOMPARE(distances.at(0).toString(), QStringLiteral("120.50"));
            QCOMPARE(distances.at(1).toString(), QStringLiteral("119.00"));
            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }
    void ingestCoordinatorBuildsCardsAndCachesImages()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        auto touch = [&](const QString &name) {
            QFile file(dir.filePath(name));
            return file.open(QIODevice::WriteOnly);
        };

        IngestCoordinator::PendingImageCache cache;
        const QDateTime now = QDateTime::currentDateTime();
        QVERIFY(touch(QStringLiteral("Cam01.PNG")));
        QVERIFY(touch(QStringLiteral("old.png")));
        cache.add(QStringLiteral("Cam01.PNG"), dir.filePath(QStringLiteral("Cam01.PNG")), now);
        cache.add(QStringLiteral("old.png"), dir.filePath(QStringLiteral("old.png")), now.addSecs(-IngestCoordinator::PendingImageCache::kMaxAgeSecs - 1));
        cache.add(QStringLiteral("gone.png"), dir.filePath(QStringLiteral("gone.png")), now);
        QCOMPARE(cache.size(), 3);
        QCOMPARE(cache.find(QStringLiteral("some/dir/cam01.png")), dir.filePath(QStringLiteral("Cam01.PNG")));
        QVERIFY(cache.find(QStringLiteral("gone.png")).isEmpty());
        cache.prune(now);
        QCOMPARE(cache.size(), 1); // 超时与已删除的文件被丢弃

        for (int i = 0; i < IngestCoordinator::PendingImageCache::kMaxEntries + 5; ++i) {
            const QString name = QStringLiteral("bulk_%1.png").arg(i);
            QVERIFY(touch(name));
            cache.add(name, dir.filePath(name), now.addMSecs(i));
        }
        cache.prune(now);
        QCOMPARE(cache.size(), IngestCoordinator::PendingImageCache::kMaxEntries);
        QVERIFY(cache.find(QStringLiteral("cam01.png")).isEmpty()); // 最早的条目先被淘汰
        QVERIFY(!cache.find(QStringLiteral("bulk_516.png")).isEmpty());

        ImageIngest::BatchData batch;
        batch.carrierId = 3;
        batch.batchId = QStringLiteral("b1");
        auto wheel = [](int wheelId, int cameraId, int result, const QString &image) {
            ImageIngest::WheelItem item;
            item.wheelId = wheelId;
            item.cameraId = cameraId;
            item.result = result;
            item.actualDistance = 120.0 + wheelId;
            item.imageName = image;
            return item;
        };
        batch.wheels = {wheel(1, 1, 1, QStringLiteral("cam01.png")), wheel(2, 1, 0, QStringLiteral("cam01.png")),
                        wheel(3, 2, 1, QStringLiteral("cam02.png")), wheel(4, 13, 0, QStringLiteral("x.png"))};
        QStringList located;
        const QVector<ImageItem> cards = IngestCoordinator::buildStationCards(batch, [&](const QString &name) {
            located << name;
            return name == QStringLiteral("cam02.png") ? dir.filePath(QStringLiteral("Cam01.PNG")) : QString();
        });
        QCOMPARE(cards.size(), 12);
        QCOMPARE(cards.at(0).result, 0);                 // 同一相机任一轮 NG 则整卡 NG
        QCOMPARE(cards.at(0).wheelId, 1);                // 卡片取该相机第一条轮数据
        QCOMPARE(cards.at(0).wheelsInfo, QStringLiteral("轮1: 121.0mm (OK) ╎ 轮2: 122.0mm (NG)"));
        QVERIFY(cards.at(0).filePath.isEmpty());
        QCOMPARE(cards.at(1).result, 1);
        QCOMPARE(cards.at(1).filePath, dir.filePath(QStringLiteral("Cam01.PNG")));
        QCOMPARE(cards.at(11).serial, QStringLiteral("CAM 12"));
        QVERIFY(cards.at(11).wheelsInfo.isEmpty());
        QVERIFY(!located.contains(QStringLiteral("x.png"))); // 相机号越界的轮数据被忽略
    }
    void storageMonitorLevelsAndUsage()
    {
        using StorageMonitor::Level;
        QCOMPARE(StorageMonitor::levelFor(50.0, 10, 5, 2), Level::Ok);
        QCOMPARE(StorageMonitor::levelFor(9.9, 10, 5, 2), Level::Warn);
        QCOMPARE(StorageMonitor::levelFor(4.0, 10, 5, 2), Level::RejectUploads);
        QCOMPARE(StorageMonitor::levelFor(1.5, 10, 5, 2), Level::RejectData);
        QCOMPARE(StorageMonitor::levelFor(10.0, 10, 5, 2), Level::Ok); // 等于阈值不告警

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        // 尚不存在的子目录按其最近的已存在父目录所在分区计算
        const StorageMonitor::Usage usage = StorageMonitor::lowest({QString(), dir.filePath(QStringLiteral("not/yet/created"))});
        QVERIFY(usage.valid);
        QVERIFY(usage.totalBytes > 0);
        QVERIFY(usage.freePercent >= 0.0 && usage.freePercent <= 100.0);
        QVERIFY(!StorageMonitor::lowest({}).valid);
    }
    void networkAccessAllowListAndThrottle()
    {
        bool ok = false;
        QString error;
        QVERIFY(NetworkAccess::parseAllowList(QString(), ok, error).isEmpty());
        QVERIFY(ok);
        const auto list = NetworkAccess::parseAllowList(QStringLiteral("192.168.1.0/24, 10.0.0.5;::1"), ok, error);
        QVERIFY(ok);
        QCOMPARE(list.size(), 3);
        QVERIFY(NetworkAccess::isAllowed(QHostAddress(QStringLiteral("192.168.1.77")), list));
        QVERIFY(NetworkAccess::isAllowed(QHostAddress(QStringLiteral("::ffff:192.168.1.9")), list)); // IPv4 映射地址
        QVERIFY(NetworkAccess::isAllowed(QHostAddress(QStringLiteral("10.0.0.5")), list));
        QVERIFY(!NetworkAccess::isAllowed(QHostAddress(QStringLiteral("10.0.0.6")), list));
        QVERIFY(NetworkAccess::isAllowed(QHostAddress(QStringLiteral("10.0.0.6")), {})); // 空列表不限制
        NetworkAccess::parseAllowList(QStringLiteral("192.168.1.0/24,not-an-ip"), ok, error);
        QVERIFY(!ok);
        QVERIFY(error.contains(QStringLiteral("not-an-ip")));

        NetworkAccess::LoginThrottle throttle(3, 600, 900);
        const QDateTime t0 = QDateTime::fromString(QStringLiteral("2026-10-20T12:00:00"), Qt::ISODate);
        QVERIFY(!throttle.recordFailure(QStringLiteral("1.1.1.1"), t0));
        QVERIFY(!throttle.recordFailure(QStringLiteral("1.1.1.1"), t0.addSecs(10)));
        QVERIFY(throttle.recordFailure(QStringLiteral("1.1.1.1"), t0.addSecs(20)));     // 第 3 次封禁
        QVERIFY(throttle.isBanned(QStringLiteral("1.1.1.1"), t0.addSecs(30)));
        QVERIFY(!throttle.isBanned(QStringLiteral("2.2.2.2"), t0.addSecs(30)));
        QVERIFY(!throttle.isBanned(QStringLiteral("1.1.1.1"), t0.addSecs(20 + 901)));  // 封禁到期
        // 窗口外的失败重新计数
        QVERIFY(!throttle.recordFailure(QStringLiteral("3.3.3.3"), t0));
        QVERIFY(!throttle.recordFailure(QStringLiteral("3.3.3.3"), t0.addSecs(10)));
        QVERIFY(!throttle.recordFailure(QStringLiteral("3.3.3.3"), t0.addSecs(700)));
        QVERIFY(!throttle.isBanned(QStringLiteral("3.3.3.3"), t0.addSecs(700)));
    }

    void latestRoundImagesGroupsTwoTriggersPerRack()
    {
        QTemporaryDir imageDir;
        QVERIFY(imageDir.isValid());
        const QString connectionName = QStringLiteral("TestRoundImagesDb");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(QStringLiteral(":memory:"));
            QVERIFY(db.open());
            QVERIFY(DBSchema::ensureAllTables(db));

            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,distance,imagename) "
                "VALUES(:time,:rack,:cam,:wheel,:result,:distance,:image)"));
            auto add = [&](const QString &time, int rack, int cam, int wheel, int result, const QString &image,
                           bool createFile) {
                if (createFile) {
                    QFile file(QDir(imageDir.path()).filePath(image));
                    if (!file.exists() && (!file.open(QIODevice::WriteOnly) || file.write("x") != 1)) return false;
                }
                insert.bindValue(QStringLiteral(":time"), time);
                insert.bindValue(QStringLiteral(":rack"), rack);
                insert.bindValue(QStringLiteral(":cam"), cam);
                insert.bindValue(QStringLiteral(":wheel"), wheel);
                insert.bindValue(QStringLiteral(":result"), result);
                insert.bindValue(QStringLiteral(":distance"), 120.0 + wheel);
                insert.bindValue(QStringLiteral(":image"), image);
                return insert.exec();
            };

            // 上一轮：12 个相机齐全，均不应出现在本轮
            for (int cam = 1; cam <= 12; ++cam)
                QVERIFY(add(QStringLiteral("2026-09-04 09:50:00"), 3, cam, cam, 1,
                            QStringLiteral("old_cam%1.png").arg(cam), true));
            // 本轮第一次触发：相机 1~6；相机 2 一张图覆盖轮 3（OK）和轮 4（NG）
            for (int cam = 1; cam <= 6; ++cam)
                QVERIFY(add(QStringLiteral("2026-09-04 10:00:00"), 3, cam, cam, 1,
                            QStringLiteral("r3_cam%1.png").arg(cam), true));
            QVERIFY(add(QStringLiteral("2026-09-04 10:00:00"), 3, 2, 12, 0, QStringLiteral("r3_cam2.png"), false));
            // 本轮第二次触发：相机 7~11，相机 7 的图片尚未到达，相机 12 未上报
            QVERIFY(add(QStringLiteral("2026-09-04 10:01:00"), 3, 7, 7, 1, QStringLiteral("r3_cam7.png"), false));
            for (int cam = 8; cam <= 11; ++cam)
                QVERIFY(add(QStringLiteral("2026-09-04 10:01:00"), 3, cam, cam, 1,
                            QStringLiteral("r3_cam%1.png").arg(cam), true));

            const QVariantList racks = SearchService::latestRoundImages(db, imageDir.path(), imageDir.path());
            QCOMPARE(racks.size(), 50);

            const QVariantMap rack3 = racks.at(2).toMap();
            QCOMPARE(rack3.value("rack").toInt(), 3);
            QCOMPARE(rack3.value("time").toString(), QStringLiteral("2026-09-04 10:01:00"));
            QCOMPARE(rack3.value("cameraCount").toInt(), 11);
            QCOMPARE(rack3.value("imageCount").toInt(), 10);
            QCOMPARE(rack3.value("ngCount").toInt(), 1);
            QCOMPARE(rack3.value("status").toString(), QStringLiteral("ng"));

            const QVariantList images = rack3.value("images").toList();
            QCOMPARE(images.size(), 12);
            const QVariantMap cam2 = images.at(1).toMap();
            QCOMPARE(cam2.value("cameraId").toInt(), 2);
            QCOMPARE(cam2.value("result").toInt(), 0);
            QCOMPARE(cam2.value("wheels").toStringList().size(), 2);
            QVERIFY(cam2.value("hasImage").toBool());
            QCOMPARE(cam2.value("time").toString(), QStringLiteral("2026-09-04 10:00:00"));
            QVERIFY(images.at(6).toMap().value("hasRecord").toBool());
            QVERIFY(!images.at(6).toMap().value("hasImage").toBool());
            QVERIFY(!images.at(11).toMap().value("hasRecord").toBool());
            QCOMPARE(images.at(0).toMap().value("fileName").toString(), QStringLiteral("r3_cam1.png"));

            const QVariantMap rack5 = racks.at(4).toMap();
            QCOMPARE(rack5.value("status").toString(), QStringLiteral("none"));
            QCOMPARE(rack5.value("images").toList().size(), 12);
            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }
};

QTEST_GUILESS_MAIN(CoreBoundaryTests)
#include "CoreBoundaryTests.moc"
