#include <QtTest>
#include <QTemporaryDir>
#include <QImage>
#include <QBuffer>
#include <QSqlQuery>
#include <QSqlError>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include "data/DbSchema.h"
#include "common/AgcUtils.h"
#include "ingest/ImageIngest.h"
#include "data/ArchiveMaintenance.h"
#include "data/DatabaseGuard.h"
#include "network/FtpServer.h"
#include "network/FtpIngestService.h"
#include "network/TcpDataReceiver.h"
#include "common/AppLogger.h"
#include "app/ThumbnailCache.h"

class ReleaseBoundaryTests : public QObject {
    Q_OBJECT
    QSqlDatabase db;
    static QString reply(QTcpSocket &socket) {
        QElapsedTimer timer; timer.start();
        while (!socket.canReadLine() && timer.elapsed() < 3000) QTest::qWait(1);
        return QString::fromUtf8(socket.readLine()).trimmed();
    }
    static QString command(QTcpSocket &socket, const QByteArray &cmd) {
        socket.write(cmd + "\r\n"); return reply(socket);
    }
    static QString imageName(const QString &root) { return root + "/upload-sample.png"; }
    static bool makeImage(const QString &path, Qt::GlobalColor color = Qt::red) {
        QImage image(8,8,QImage::Format_RGB32); image.fill(color); return image.save(path,"PNG");
    }
private slots:
    void init() {
        db = QSqlDatabase::addDatabase("QSQLITE", "release-test");
        db.setDatabaseName(":memory:"); QVERIFY(db.open()); QVERIFY(DBSchema::ensureAllTables(db));
    }
    void cleanup() { db.close(); db = {}; QSqlDatabase::removeDatabase("release-test"); }
    void transactionRollsBackBothWheels() {
        ImageIngest::BatchData batch;
        batch.carrierId = 1;
        batch.timestamp = QDateTime::fromString("2026-09-05 10:00:00", "yyyy-MM-dd HH:mm:ss");
        batch.batchId = "BATCH_ROLLBACK_TEST";
        ImageIngest::WheelItem w1;
        w1.wheelId = 1;
        w1.cameraId = 1;
        w1.result = 0; // NG
        w1.imageName = "rollback_w1.png";
        ImageIngest::WheelItem w2;
        w2.wheelId = 2;
        w2.cameraId = 1;
        w2.result = 0; // NG
        w2.imageName = "rollback_w2.png";
        batch.wheels = {w1, w2};

        QSqlQuery q(db);
        QVERIFY(q.exec("CREATE TRIGGER fail_second BEFORE INSERT ON record WHEN NEW.wheel_id=2 BEGIN SELECT RAISE(ABORT,'injected'); END"));
        QString error;
        QVERIFY(!ImageIngest::recordBatch(db, batch, error));
        for (const auto &table : {"record","alertrecord"}) {
            QVERIFY(q.exec(QString("SELECT COUNT(*) FROM %1").arg(table))); QVERIFY(q.next()); QCOMPARE(q.value(0).toInt(),0);
        }
        QVERIFY(q.exec("DROP TRIGGER fail_second"));
        QVERIFY(ImageIngest::recordBatch(db, batch, error));
        QVERIFY(q.exec("SELECT COUNT(*) FROM record WHERE batch_id='BATCH_ROLLBACK_TEST'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 2);
    }
    void batchJsonRejectsInvalidAndOversizedPayloads() {
        ImageIngest::BatchData batch;
        QString error;
        QJsonObject wheel{{"wheelId", 1}, {"cameraId", 1}, {"result", "OK"}, {"imageName", "cam01.png"}};
        QJsonObject root{{"carrierId", 1}, {"wheels", QJsonArray{wheel}}};
        QVERIFY(ImageIngest::parseBatchJson(root, batch, error));

        // imageName：带路径时只取文件名；空名、. 开头、非图片扩展名拒收
        auto imageNameResult = [&](const QString &name) {
            QJsonObject w = wheel; w["imageName"] = name;
            QJsonObject r = root; r["wheels"] = QJsonArray{w};
            return ImageIngest::parseBatchJson(r, batch, error) ? batch.wheels.first().imageName : QStringLiteral("<rejected>");
        };
        QCOMPARE(imageNameResult("D:\\cam\\A_1.png"), QStringLiteral("A_1.png"));
        QCOMPARE(imageNameResult("/data/cam/../A_2.JPG"), QStringLiteral("A_2.JPG"));
        QCOMPARE(imageNameResult(""), QStringLiteral("<rejected>"));
        QCOMPARE(imageNameResult("cam/"), QStringLiteral("<rejected>"));
        QCOMPARE(imageNameResult("../.hidden.png"), QStringLiteral("<rejected>"));
        QCOMPARE(imageNameResult("report.txt"), QStringLiteral("<rejected>"));

        // 时间戳范围：未来不超过 10 分钟，过去不超过保留天数；未提供限制时不检查
        const QDateTime now = QDateTime::fromString("2026-10-20 12:00:00", "yyyy-MM-dd HH:mm:ss");
        ImageIngest::ParseLimits limits;
        limits.now = now;
        limits.maxAgeDays = 90;
        auto timestampOk = [&](const QDateTime &time) {
            QJsonObject r = root; r["timestamp"] = time.toString("yyyyMMdd_HHmmss");
            return ImageIngest::parseBatchJson(r, batch, error, limits);
        };
        QVERIFY(timestampOk(now.addSecs(300)));
        QVERIFY(!timestampOk(now.addSecs(900)));
        QVERIFY(timestampOk(now.addDays(-89)));
        QVERIFY(!timestampOk(now.addDays(-91)));
        QJsonObject future = root; future["timestamp"] = "20990101_000000";
        QVERIFY(ImageIngest::parseBatchJson(future, batch, error));
        QVERIFY(!ImageIngest::parseBatchJson(future, batch, error, limits));
        QVERIFY(error.contains(QStringLiteral("客户端时钟")));

        for (const int invalidWheel : {0, 17, 18}) {
            wheel["wheelId"] = invalidWheel;
            root["wheels"] = QJsonArray{wheel};
            QVERIFY(!ImageIngest::parseBatchJson(root, batch, error));
        }
        wheel["wheelId"] = 1;

        root["carrierId"] = 1.5;
        QVERIFY(!ImageIngest::parseBatchJson(root, batch, error));
        root["carrierId"] = 1;
        wheel["result"] = "UNKNOWN";
        root["wheels"] = QJsonArray{wheel};
        QVERIFY(!ImageIngest::parseBatchJson(root, batch, error));
        wheel["result"] = "OK";
        wheel["cameraId"] = 13;
        root["wheels"] = QJsonArray{wheel};
        QVERIFY(!ImageIngest::parseBatchJson(root, batch, error));
        QJsonArray tooMany;
        wheel["cameraId"] = 1;
        for (int i = 0; i < 33; ++i) {
            QJsonObject entry = wheel;
            entry["wheelId"] = i % 16 + 1;
            entry["cameraId"] = i % 12 + 1;
            tooMany.append(entry);
        }
        root["wheels"] = tooMany;
        QVERIFY(!ImageIngest::parseBatchJson(root, batch, error));
    }
    void requestIdMakesBatchInsertIdempotent() {
        ImageIngest::BatchData batch;
        batch.carrierId = 2;
        batch.timestamp = QDateTime::currentDateTime();
        batch.batchId = "batch-idempotent";
        batch.requestId = "request-uuid-1";
        ImageIngest::WheelItem wheel;
        wheel.wheelId = 1;
        wheel.cameraId = 1;
        wheel.result = 1;
        wheel.imageName = "one.png";
        batch.wheels = {wheel};
        QString error;
        QVERIFY2(ImageIngest::recordBatch(db, batch, error), qPrintable(error));
        QVERIFY2(ImageIngest::recordBatch(db, batch, error), qPrintable(error));
        QSqlQuery q(db);
        QVERIFY(q.exec("SELECT COUNT(*) FROM record WHERE batch_id='batch-idempotent'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 1);

        batch.wheels.append(wheel);
        QVERIFY(!ImageIngest::recordBatch(db, batch, error));
    }
    void lateNgCannotResurrectOldAlert() {
        QSqlQuery q(db);
        QVERIFY(q.exec("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-09-05 11:00:00',1,1,1,1,'new.png')"));
        QVERIFY(q.exec("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-09-05T10:00:00',1,1,1,0,'old.png')"));
        QVERIFY(q.exec("SELECT COUNT(*) FROM alertrecord")); QVERIFY(q.next()); QCOMPARE(q.value(0).toInt(),0);
        q.finish(); QVERIFY(DBSchema::ensureAllTables(db)); // existing installation migration is repeatable
    }
    void immutableUploadAndRetryJournal() {
        QTemporaryDir dir; QVERIFY(dir.isValid()); QString error;
        const QString target = imageName(dir.path()), staged = dir.filePath("staged");
        QVERIFY(makeImage(staged));
        QVERIFY(!ImageIngest::accept(staged,target,[](const QString&){return false;},error));
        QVERIFY(QFile::exists(target)); QVERIFY(QFile::exists(target+".cv-pending"));
        QVERIFY(makeImage(staged,Qt::blue));
        QVERIFY(!ImageIngest::accept(staged,target,[](const QString&){return true;},error));
        QCOMPARE(QImage(target).pixelColor(0,0),QColor(Qt::red));
        QVERIFY(makeImage(staged));
        QVERIFY(ImageIngest::accept(staged,target,[](const QString&){return true;},error));
        QVERIFY(!QFile::exists(target+".cv-pending"));
    }
    void corruptImageNeverReplacesHistory() {
        QTemporaryDir dir; QString error;
        const QString target = imageName(dir.path()), staged = dir.filePath("broken");
        QVERIFY(makeImage(target)); QFile f(staged); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("not an image"); f.close();
        QVERIFY(!ImageIngest::accept(staged,target,[](const QString&){return true;},error));
        QCOMPARE(QImage(target).pixelColor(0,0),QColor(Qt::red));
    }
    void cleanupKeepsNewFilesInOldParent() {
        QTemporaryDir dir; QVERIFY(QDir().mkpath(dir.filePath("camera/deep")));
        const QString old = "camera/deep/old.png", fresh = "camera/deep/new.png";
        QVERIFY(makeImage(dir.filePath(old))); QVERIFY(makeImage(dir.filePath(fresh)));
        QSqlQuery q(db);
        q.prepare("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES(:t,1,1,1,1,:n)");
        q.bindValue(":t","2026-06-07 00:00:00"); q.bindValue(":n",old); QVERIFY(q.exec());
        q.bindValue(":t","2026-06-07 23:59:59"); q.bindValue(":n",fresh); QVERIFY(q.exec()); q.finish();
        int removed; bool more; QString error;
        QVERIFY2(ArchiveMaintenance::cleanup(db,dir.path(),{dir.path()},QDateTime::fromString("2026-06-07T01:00:00",Qt::ISODate),removed,more,error),qPrintable(error));
        QCOMPARE(removed,1); QVERIFY(!QFile::exists(dir.filePath(old))); QVERIFY(QFile::exists(dir.filePath(fresh)));
        QVERIFY(QDir(dir.filePath("camera/deep")).exists());
        QVERIFY(q.exec("SELECT COUNT(*) FROM record")); QVERIFY(q.next()); QCOMPARE(q.value(0).toInt(),1);
    }
    void cleanupRecoveryHonorsNewReference() {
        QTemporaryDir dir; const QString target = dir.filePath("keep.png"); QVERIFY(makeImage(target));
        QSqlQuery q(db);
        q.prepare("INSERT INTO cleanup_files(path,imagename) VALUES(:path,'keep.png')"); q.bindValue(":path",target); QVERIFY(q.exec());
        QVERIFY(q.exec("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-09-05 11:00:00',1,1,1,1,'keep.png')"));
        int removed; bool more; QString error;
        QVERIFY(ArchiveMaintenance::cleanup(db,dir.path(),{dir.path()},QDateTime::fromString("2026-06-07T01:00:00",Qt::ISODate),removed,more,error));
        QVERIFY(QFile::exists(target)); QCOMPARE(removed,0);
    }
    void cleanupProgressesPastUnsafePathsAndUsesImagePath() {
        QTemporaryDir dir; QVERIFY(QDir().mkpath(dir.filePath("cam1")));
        QSqlQuery q(db);
        q.prepare("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename,image_path) VALUES(:t,1,1,1,1,:n,:p)");
        auto add = [&](const QString &time, const QString &name, const QVariant &path) {
            q.bindValue(":t", time); q.bindValue(":n", name); q.bindValue(":p", path); return q.exec();
        };
        // 500 组路径不安全的过期记录（历史数据中的绝对路径与 ../），曾导致清理永久停滞
        for (int i = 0; i < 500; ++i)
            QVERIFY(add("2025-01-01 00:00:00", (i % 2 ? "/data/cam/A_%1.png" : "../cam/A_%1.png") + QString::number(i), QVariant()));
        QVERIFY(makeImage(dir.filePath("normal.png")));
        QVERIFY(add("2025-01-01 00:00:00", "normal.png", QVariant()));
        // 实际落盘在子目录、且被版本化的文件：按 image_path 清理
        const QString versioned = dir.filePath("cam1/x_v2.png");
        QVERIFY(makeImage(versioned));
        QVERIFY(add("2025-01-01 00:00:00", "x.png", versioned));
        q.finish();

        const QDateTime cutoff = QDateTime::fromString("2026-01-01T00:00:00", Qt::ISODate);
        int removed = 0; bool more = false; QString error;
        ArchiveMaintenance::CleanupStats stats;
        int rounds = 0;
        do {
            QVERIFY2(ArchiveMaintenance::cleanup(db, dir.path(), {dir.path()}, cutoff, removed, more, error, &stats), qPrintable(error));
        } while (more && ++rounds < 5);
        QVERIFY(!QFile::exists(dir.filePath("normal.png")));
        QVERIFY(!QFile::exists(versioned));
        QVERIFY(q.exec("SELECT COUNT(*) FROM record")); QVERIFY(q.next()); QCOMPARE(q.value(0).toInt(), 0);
    }
    void orphanSweepDeletesOnlyOldUnreferencedImages() {
        QTemporaryDir dir; QVERIFY(QDir().mkpath(dir.filePath("sub")));
        const QDateTime old = QDateTime::currentDateTime().addDays(-200);
        auto makeOld = [&](const QString &rel) {
            const QString path = dir.filePath(rel);
            if (!makeImage(path)) return false;
            QFile f(path);
            return f.open(QIODevice::ReadWrite) && f.setFileTime(old, QFileDevice::FileModificationTime);
        };
        QVERIFY(makeOld("orphan.png"));
        QVERIFY(makeOld("sub/orphan_v2.png"));
        QVERIFY(makeOld("by_name.png"));
        QVERIFY(makeOld("by_path.png"));
        QVERIFY(makeOld("pending.png"));
        QFile marker(dir.filePath("pending.png.cv-pending")); QVERIFY(marker.open(QIODevice::WriteOnly)); marker.close();
        QVERIFY(makeImage(dir.filePath("fresh.png")));
        QSqlQuery q(db);
        QVERIFY(q.exec("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-01-01 00:00:00',1,1,1,1,'by_name.png')"));
        q.prepare("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename,image_path) VALUES('2026-01-01 00:00:00',1,1,2,1,'other.png',:p)");
        q.bindValue(":p", QFileInfo(dir.filePath("by_path.png")).canonicalFilePath()); QVERIFY(q.exec());
        QString error;
        const int deleted = ArchiveMaintenance::sweepOrphans(db, {dir.path(), dir.path()}, QDateTime::currentDateTime().addDays(-97), 100, error);
        QCOMPARE(deleted, 2);
        QVERIFY(!QFile::exists(dir.filePath("orphan.png")));
        QVERIFY(!QFile::exists(dir.filePath("sub/orphan_v2.png")));
        for (const char *kept : {"by_name.png", "by_path.png", "pending.png", "fresh.png"})
            QVERIFY2(QFile::exists(dir.filePath(kept)), kept);
        QVERIFY(QDir(dir.filePath("sub")).exists());
    }
    void validateRejectsTruncatedImages() {
        QTemporaryDir dir; QString error;
        QImage image(64, 48, QImage::Format_RGB32); image.fill(Qt::darkCyan);
        for (const char *fmt : {"jpg", "png", "bmp"}) {
            const QString path = dir.filePath(QString("full.%1").arg(fmt));
            QVERIFY(image.save(path, fmt));
            QVERIFY2(ImageIngest::validate(path, path, error), qPrintable(error));
            QFile f(path); QVERIFY(f.open(QIODevice::ReadOnly)); const QByteArray data = f.readAll(); f.close();
            const QString cut = dir.filePath(QString("cut.%1").arg(fmt));
            QFile c(cut); QVERIFY(c.open(QIODevice::WriteOnly)); c.write(data.left(data.size() * 2 / 3)); c.close();
            QVERIFY2(!ImageIngest::validate(cut, cut, error), fmt);
            if (QByteArray(fmt) == "jpg") {
                // 部分相机在 JPEG 结束标记后补零：仍应接受
                const QString padded = dir.filePath("padded.jpg");
                QFile p(padded); QVERIFY(p.open(QIODevice::WriteOnly)); p.write(data + QByteArray(64, '\0')); p.close();
                QVERIFY2(ImageIngest::validate(padded, padded, error), qPrintable(error));
            }
        }
    }
    void ftpLocksOutRepeatedFailuresAndUsesPassiveRange() {
        QTemporaryDir dir; FtpServer server;
        server.setPassivePortRange(52300, 52310);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0, dir.path(), QMap<QString,QString>{{"u","p"}}));
        // 被动端口落在配置范围内
        {
            QTcpSocket client; client.connectToHost(QHostAddress::LocalHost, server.port());
            QVERIFY(reply(client).startsWith("220"));
            QVERIFY(command(client, "USER u").startsWith("331"));
            QVERIFY(command(client, "PASS p").startsWith("230"));
            const quint16 port = command(client, "EPSV").section('|', 3, 3).toUShort();
            QVERIFY2(port >= 52300 && port <= 52310, qPrintable(QString::number(port)));
        }
        // 每个连接失败 5 次后被断开；同一来源累计 10 次后封禁，新连接直接 421
        for (int connection = 0; connection < 2; ++connection) {
            QTcpSocket client; client.connectToHost(QHostAddress::LocalHost, server.port());
            QVERIFY(reply(client).startsWith("220"));
            for (int i = 0; i < 5; ++i) {
                command(client, "USER u");
                command(client, "PASS wrong");
            }
            QTRY_VERIFY(client.state() != QAbstractSocket::ConnectedState || !client.isValid());
        }
        QTcpSocket banned; banned.connectToHost(QHostAddress::LocalHost, server.port());
        const QString bannedReply = reply(banned);
        QVERIFY2(bannedReply.startsWith("421"), qPrintable(bannedReply));
        server.stop();
    }
    void databaseBackupAndCorruptionRecovery() {
        QTemporaryDir dir;
        const QString dbPath = dir.filePath("dataAgc.db");
        const QString backupDir = dir.filePath("backup");
        {
            QSqlDatabase file = QSqlDatabase::addDatabase("QSQLITE", "guard-test");
            file.setDatabaseName(dbPath);
            QVERIFY(file.open());
            QVERIFY(DBSchema::ensureAllTables(file));
            QSqlQuery q(file);
            QVERIFY(q.exec("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-10-01 00:00:00',1,1,1,1,'kept.png')"));
            QVERIFY(file.transaction());
            for (int i = 0; i < 2000; ++i)
                QVERIFY(q.exec(QString("INSERT INTO record(createtime,carrier_id,camera_id,wheel_id,result,imagename) VALUES('2026-10-01 00:00:00',1,1,1,1,'pad_%1.png')").arg(i)));
            QVERIFY(file.commit());
            QString detail; QVERIFY(DatabaseGuard::quickCheck(file, detail));
            QString error, created;
            for (int i = 0; i < 4; ++i) {
                QVERIFY2(DatabaseGuard::backup(file, backupDir, 3, error, &created), qPrintable(error));
                QTest::qWait(1100); // 备份文件名精确到秒
            }
            QCOMPARE(DatabaseGuard::backups(backupDir).size(), 3);   // 只保留最近 3 份
            QCOMPARE(DatabaseGuard::backups(backupDir).first(), created);
            file.close();
        }
        QSqlDatabase::removeDatabase("guard-test");

        QVERIFY(DatabaseGuard::recoverIfCorrupt(dbPath, backupDir).isEmpty()); // 正常库不处理

        // 破坏数据页（保留文件头，使其仍能打开但检查失败）
        QFile f(dbPath); QVERIFY(f.open(QIODevice::ReadWrite));
        const qint64 size = f.size();
        QVERIFY(f.seek(size / 2)); QVERIFY(f.write(QByteArray(8192, '\x5a')) == 8192); f.close();

        const QString message = DatabaseGuard::recoverIfCorrupt(dbPath, backupDir);
        QVERIFY2(message.contains("已从备份"), qPrintable(message));
        QVERIFY(!QDir(dir.path()).entryList({"dataAgc.db.corrupt-*"}, QDir::Files).isEmpty()); // 原文件保留
        {
            QSqlDatabase restored = QSqlDatabase::addDatabase("QSQLITE", "guard-restored");
            restored.setDatabaseName(dbPath);
            QVERIFY(restored.open());
            QString detail; QVERIFY(DatabaseGuard::quickCheck(restored, detail));
            QSqlQuery q(restored);
            QVERIFY(q.exec("SELECT COUNT(*) FROM record WHERE imagename='kept.png'")); QVERIFY(q.next());
            QCOMPARE(q.value(0).toInt(), 1);
            restored.close();
        }
        QSqlDatabase::removeDatabase("guard-restored");
    }
    void logsUseNumericVolumesAndBoundedPagination() {
        QTemporaryDir dir;
        AppLogger::init(dir.path()); AppLogger::shutdown();
        for (const auto &entry : QList<QPair<QString,QString>>{{"", "00"},{".2","02"},{".10","10"}}) {
            QFile file(dir.filePath("carrier_2025-01-01"+entry.first+".log"));
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(("[2025-01-01 10:00:"+entry.second+".000] [info] volume"+entry.second+"\n").toUtf8());
        }
        auto result=AppLogger::queryLogs("2025-01-01","all","",1,2);
        QCOMPARE(result["total"].toInt(),3);
        auto items=result["items"].toList(); QCOMPARE(items.size(),2);
        QCOMPARE(items[0].toMap()["message"].toString(),QString("volume10"));
        QCOMPARE(items[1].toMap()["message"].toString(),QString("volume02"));
        result=AppLogger::queryLogs("2025-01-01","all","",2147483647,2147483647);
        QCOMPARE(result["pageSize"].toInt(),200); QVERIFY(result["items"].toList().isEmpty());
        QVERIFY(AppLogger::queryLogs("*","all","",1,2).contains("error"));
    }
    void ftpTimeoutReleasesCountExactlyOnce() {
        QTemporaryDir dir; FtpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost,0,dir.path(),QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost,server.port());
        QVERIFY(reply(client).startsWith("220")); QCOMPARE(server.clientCount(),1);
        auto session = server.findChild<FtpControlConnection*>(); QVERIFY(session);
        session->findChild<QTimer*>()->start(1);
        QTRY_COMPARE(server.clientCount(),0);
        QTRY_VERIFY(server.findChildren<FtpControlConnection*>().isEmpty());
        server.stop(); QCOMPARE(server.clientCount(),0);
    }
    void ftpDelayedDataConnectionDoesNotBlockEventLoop() {
        QTemporaryDir dir; FtpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost,0,dir.path(),QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost,server.port()); QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client,"USER u").startsWith("331")); QVERIFY(command(client,"PASS p").startsWith("230"));
        QString epsv = command(client,"EPSV"); QVERIFY(epsv.startsWith("229"));
        const auto port = epsv.section('|',3,3).toUShort(); QVERIFY(port);
        bool tick = false; QTimer::singleShot(20,[&] {tick=true;});
        QVERIFY(command(client,"LIST").startsWith("150"));
        QTRY_VERIFY_WITH_TIMEOUT(tick,500);
        QTcpSocket data; data.connectToHost(QHostAddress::LocalHost,port);
        QVERIFY(reply(client).startsWith("226"));
        server.stop();
    }
    void ftpRetrStreamsCompleteContentAndAbortDropsPartialUpload() {
        QTemporaryDir dir; FtpServer server;
        QByteArray expected(2*1024*1024,'x');
        QFile source(dir.filePath("download.bin")); QVERIFY(source.open(QIODevice::WriteOnly)); QCOMPARE(source.write(expected),qint64(expected.size())); source.close();
        QVERIFY(server.listen(QHostAddress::LocalHost,0,dir.path(),QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost,server.port()); QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client,"USER u").startsWith("331")); QVERIFY(command(client,"PASS p").startsWith("230"));
        const QString epsv=command(client,"EPSV");
        QTcpSocket data; data.connectToHost(QHostAddress::LocalHost,epsv.section('|',3,3).toUShort());
        QTRY_COMPARE(data.state(),QAbstractSocket::ConnectedState);
        QVERIFY(command(client,"RETR download.bin").startsWith("150"));
        QByteArray received;
        QElapsedTimer timer; timer.start();
        while (received.size()<expected.size() && timer.elapsed()<3000) { received+=data.readAll(); QTest::qWait(1); }
        QCOMPARE(received,expected); QVERIFY(reply(client).startsWith("226"));
        const QString second=command(client,"EPSV");
        QTcpSocket upload; upload.connectToHost(QHostAddress::LocalHost,second.section('|',3,3).toUShort());
        QTRY_COMPARE(upload.state(),QAbstractSocket::ConnectedState);
        QVERIFY(command(client,"STOR upload-sample.png").startsWith("150"));
        upload.write("partial image");
        QVERIFY(command(client,"ABOR").startsWith("226"));
        QVERIFY(!QFile::exists(imageName(dir.path())));
        QVERIFY(!QFile::exists(imageName(dir.path())+".cv-pending"));
        QTRY_VERIFY(QDir(dir.path()).entryList({".cv-upload-*"},QDir::Files|QDir::Hidden).isEmpty());
        server.stop();
    }
    void ftpUploadAndCredentialRevocation() {
        QTemporaryDir dir; FtpServer server; QString error;
        server.uploadHandler = [&](const QString &staged,const QString &target,const QString &) { return ImageIngest::accept(staged,target,[](const QString&){return true;},error); };
        QVERIFY(server.listen(QHostAddress::LocalHost,0,dir.path(),QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost,server.port()); QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client,"USER u").startsWith("331")); QVERIFY(command(client,"PASS p").startsWith("230"));
        QString epsv=command(client,"EPSV"); const auto port=epsv.section('|',3,3).toUShort(); QVERIFY(port);
        QTcpSocket data; data.connectToHost(QHostAddress::LocalHost,port);
        QTRY_COMPARE(data.state(),QAbstractSocket::ConnectedState);
        auto *session = server.findChild<FtpControlConnection*>(); QVERIFY(session);
        QTRY_VERIFY(session->findChild<QTcpSocket*>());
        QCOMPARE(session->findChild<QTcpSocket*>()->readBufferSize(),qint64(256*1024));
        QVERIFY(command(client,"STOR upload-sample.png").startsWith("150"));
        QImage image(8,8,QImage::Format_RGB32); image.fill(Qt::red); QByteArray bytes; QBuffer buffer(&bytes); QVERIFY(buffer.open(QIODevice::WriteOnly)); QVERIFY(image.save(&buffer,"PNG"));
        data.write(bytes); data.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"),qPrintable(error)); QVERIFY(QFile::exists(imageName(dir.path())));
        server.setUsers({}); QTRY_COMPARE(server.clientCount(),0);
        server.stop();
    }
    void ftpIngestServiceUploadsAndRecoversOnWorkerThread() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        // 上次异常退出遗留的恢复标记：图片已完整落盘，恢复扫描应补发入库通知并清除标记
        const QString recovered = dir.filePath("recovered.png");
        QVERIFY(makeImage(recovered));
        QFile marker(recovered + ".cv-pending");
        QVERIFY(marker.open(QIODevice::WriteOnly)); marker.write("x"); marker.close();

        QThread thread;
        auto *service = new FtpIngestService;
        service->moveToThread(&thread);
        connect(&thread, &QThread::finished, service, &QObject::deleteLater);
        QStringList stored, failures;
        std::atomic<QThread *> emitThread{nullptr};
        connect(service, &FtpIngestService::imageStored, service,
                [&emitThread](const QString &) { emitThread = QThread::currentThread(); }, Qt::DirectConnection);
        connect(service, &FtpIngestService::imageStored, this,
                [&stored](const QString &path) { stored << QFileInfo(path).fileName(); });
        connect(service, &FtpIngestService::ingestFailed, this,
                [&failures](const QString &error) { failures << error; });
        thread.start();

        quint16 port = 0;
        const QString root = dir.path();
        QMetaObject::invokeMethod(service, [service, root, &port]() {
            service->setRoot(root);
            if (service->start(0, root, {{"u", "p"}}, false, QHostAddress::LocalHost)) port = service->port();
        }, Qt::BlockingQueuedConnection);
        QVERIFY(port);

        QTRY_VERIFY(stored.contains("recovered.png"));
        QVERIFY(!QFile::exists(recovered + ".cv-pending"));

        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost, port);
        QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client, "USER u").startsWith("331"));
        QVERIFY(command(client, "PASS p").startsWith("230"));
        auto upload = [&](const QByteArray &name, const QByteArray &bytes) {
            const QString epsv = command(client, "EPSV");
            QTcpSocket data; data.connectToHost(QHostAddress::LocalHost, epsv.section('|', 3, 3).toUShort());
            if (!data.waitForConnected(3000)) return QString();
            const QString started = command(client, "STOR " + name);
            if (!started.startsWith("150")) return started;
            data.write(bytes); data.flush(); data.disconnectFromHost();
            return reply(client);
        };
        QImage image(8, 8, QImage::Format_RGB32); image.fill(Qt::red);
        QByteArray png; QBuffer buffer(&png); QVERIFY(buffer.open(QIODevice::WriteOnly)); QVERIFY(image.save(&buffer, "PNG"));

        QVERIFY(upload("upload-sample.png", png).startsWith("226"));
        QTRY_VERIFY(stored.contains("upload-sample.png"));
        QVERIFY(!QFile::exists(imageName(root) + ".cv-pending"));
        QCOMPARE(emitThread.load(), &thread);

        QVERIFY(!upload("broken.png", "not an image").startsWith("226"));
        QTRY_VERIFY(!failures.isEmpty());
        QVERIFY(!stored.contains("broken.png"));

        QMetaObject::invokeMethod(service, [service]() { service->shutdown(); }, Qt::BlockingQueuedConnection);
        thread.quit();
        QVERIFY(thread.wait(5000));
    }
    void databaseDefaultsAndHelpers() {
        QCOMPARE(DBSchema::getConfig(db, "ftp/rootDirectory", ""), QString("images"));
        QCOMPARE(DBSchema::getConfigInt(db, "cleanup/keepDays", 0), 90);
        QCOMPARE(DBSchema::getConfigBool(db, "ui/isDark", true), false);

        QVERIFY(DBSchema::setConfig(db, "ui/isDark", "true"));
        QCOMPARE(DBSchema::getConfigBool(db, "ui/isDark", false), true);
        QVERIFY(DBSchema::setConfig(db, "ui/isDark", "false"));

        // verify ftp_users
        QSqlQuery q(db);
        QVERIFY(q.exec("SELECT username, password_hash FROM ftp_users"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toString(), QString("agc"));
        QVERIFY(AgcUtils::verifyEncodedPassword("123456", q.value(1).toString()));

        // verify camera_slots
        QVERIFY(q.exec("SELECT COUNT(*) FROM camera_slots"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 12);

        // verify carrier_wheel_norm (50 carriers * 16 wheels)
        QVERIFY(q.exec("SELECT COUNT(*) FROM carrier_wheel_norm"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 800);
    }
    void defaultDatabasePathIsUnderDataDirectory() {
        QString dbPath = DBSchema::defaultDatabasePath();
        QVERIFY(dbPath.endsWith("data/dataAgc.db") || dbPath.endsWith("data\\dataAgc.db"));
    }
    void carrierWheelNormDatabaseOperations() {
        QSqlQuery q(db);
        q.prepare("UPDATE carrier_wheel_norm SET standard_distance = 150.0, lower_tolerance = -2.0 WHERE carrier_id = 5 AND wheel_id = 3");
        QVERIFY(q.exec());

        q.prepare("SELECT standard_distance, lower_tolerance FROM carrier_wheel_norm WHERE carrier_id = 5 AND wheel_id = 3");
        QVERIFY(q.exec());
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toDouble(), 150.0);
        QCOMPARE(q.value(1).toDouble(), -2.0);
    }
    void recordBatchPersistence() {
        ImageIngest::BatchData batch;
        batch.carrierId = 1;
        batch.timestamp = QDateTime::fromString("2026-09-05 12:00:00", "yyyy-MM-dd HH:mm:ss");
        batch.batchId = "BATCH_1_2026-09-05 12:00:00";
        ImageIngest::WheelItem wheel;
        wheel.wheelId = 1;
        wheel.cameraId = 1;
        wheel.actualDistance = 12.5;
        wheel.baseDistance = 10.0;
        wheel.lowerTolerance = -2.0;
        wheel.result = 1; // OK
        wheel.imageName = "20260905_120000_w1.png";
        batch.wheels.append(wheel);

        QString error;
        QVERIFY(ImageIngest::recordBatch(db, batch, error));

        QSqlQuery q(db);
        QVERIFY(q.exec("SELECT carrier_id, wheel_id, distance, dist_norm, lower_tolerance, result, batch_id FROM record WHERE imagename = '20260905_120000_w1.png'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 1);
        QCOMPARE(q.value(1).toInt(), 1);
        QCOMPARE(q.value(2).toDouble(), 12.5);
        QCOMPARE(q.value(3).toDouble(), 10.0);
        QCOMPARE(q.value(4).toDouble(), -2.0);
        QCOMPARE(q.value(5).toInt(), 1);
        QCOMPARE(q.value(6).toString(), QString("BATCH_1_2026-09-05 12:00:00"));

        // verify index exists
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_record_batch'"));
        QVERIFY(q.next());
    }
    void tcpDataReceiverPacketParsing() {
        TcpDataReceiver receiver;
        QVERIFY(receiver.listen(QHostAddress::LocalHost, 0));
        const quint16 port = receiver.port();

        bool received = false;
        ImageIngest::BatchData receivedBatch;
        connect(&receiver, &TcpDataReceiver::dataBatchReceived, [&](const QJsonObject &json) {
            QString err;
            if (ImageIngest::parseBatchJson(json, receivedBatch, err)) {
                received = true;
            }
        });

        QTcpSocket client;
        client.connectToHost(QHostAddress::LocalHost, port);
        QVERIFY(client.waitForConnected(3000));

        QJsonObject root;
        root["carrierId"] = 3;
        root["timestamp"] = "20260911_120000";
        QJsonArray wheels;
        QJsonObject w;
        w["wheelId"] = 2;
        w["actualDistance"] = 11.2;
        w["baseDistance"] = 10.0;
        w["lowerTolerance"] = -1.5;
        w["result"] = "OK";
        w["imageName"] = "test_w2.png";
        wheels.append(w);
        root["wheels"] = wheels;

        QByteArray data = QJsonDocument(root).toJson(QJsonDocument::Compact) + "\n";
        client.write(data);
        client.flush();
        QTRY_VERIFY_WITH_TIMEOUT(client.bytesAvailable() > 0, 3000);
        QByteArray ack = client.readLine();
        QVERIFY(ack.contains("\"status\":\"OK\""));
        QVERIFY(received);
        QCOMPARE(receivedBatch.carrierId, 3);
        QCOMPARE(receivedBatch.wheels.size(), 1);
        QCOMPARE(receivedBatch.wheels[0].wheelId, 2);
        QCOMPARE(receivedBatch.wheels[0].actualDistance, 11.2);

        receiver.stop();
    }
    void tcpReceiverOnlyAcknowledgesSuccessfulCommit() {
        TcpDataReceiver receiver;
        receiver.batchHandler = [](const QJsonObject &, QString &error) {
            error = QStringLiteral("database unavailable");
            return false;
        };
        QVERIFY(receiver.listen(QHostAddress::LocalHost, 0));
        QTcpSocket client;
        client.connectToHost(QHostAddress::LocalHost, receiver.port());
        QVERIFY(client.waitForConnected(3000));
        QJsonObject root{{"carrierId", 3}, {"wheels", QJsonArray{QJsonObject{{"wheelId", 1}, {"result", "OK"}}}}};
        client.write(QJsonDocument(root).toJson(QJsonDocument::Compact) + '\n');
        QTRY_VERIFY_WITH_TIMEOUT(client.canReadLine(), 3000);
        const QJsonObject response = QJsonDocument::fromJson(client.readLine()).object();
        QCOMPARE(response.value("status").toString(), QString("ERROR"));
        QVERIFY(response.value("message").toString().contains("database"));
        receiver.stop();
    }
    void collisionSafeFtpUpload() {
        QTemporaryDir dir; FtpServer server; QString error;
        server.uploadHandler = [&](const QString &staged, const QString &target, const QString &) {
            return ImageIngest::accept(staged, target, [](const QString&){ return true; }, error);
        };
        QVERIFY(server.listen(QHostAddress::LocalHost, 0, dir.path(), QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost, server.port());
        QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client, "USER u").startsWith("331"));
        QVERIFY(command(client, "PASS p").startsWith("230"));

        // First upload: red image
        QString epsv = command(client, "EPSV");
        QTcpSocket data1; data1.connectToHost(QHostAddress::LocalHost, epsv.section('|', 3, 3).toUShort());
        QTRY_COMPARE(data1.state(), QAbstractSocket::ConnectedState);
        QVERIFY(command(client, "STOR collision-sample.png").startsWith("150"));
        QImage redImg(8, 8, QImage::Format_RGB32); redImg.fill(Qt::red);
        QByteArray redBytes; QBuffer buf1(&redBytes); buf1.open(QIODevice::WriteOnly); redImg.save(&buf1, "PNG");
        data1.write(redBytes); data1.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"), qPrintable(error));
        const QString path1 = dir.filePath("collision-sample.png");
        QVERIFY(QFile::exists(path1));

        // Second upload with same name but different content: blue image
        epsv = command(client, "EPSV");
        QTcpSocket data2; data2.connectToHost(QHostAddress::LocalHost, epsv.section('|', 3, 3).toUShort());
        QTRY_COMPARE(data2.state(), QAbstractSocket::ConnectedState);
        QVERIFY(command(client, "STOR collision-sample.png").startsWith("150"));
        QImage blueImg(8, 8, QImage::Format_RGB32); blueImg.fill(Qt::blue);
        QByteArray blueBytes; QBuffer buf2(&blueBytes); buf2.open(QIODevice::WriteOnly); blueImg.save(&buf2, "PNG");
        data2.write(blueBytes); data2.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"), qPrintable(error));

        // Both original and version-suffixed files must exist without data loss
        const QString path2 = dir.filePath("collision-sample_v2.png");
        QVERIFY(QFile::exists(path1));
        QVERIFY(QFile::exists(path2));
        QCOMPARE(QImage(path1).pixelColor(0, 0), QColor(Qt::red));
        QCOMPARE(QImage(path2).pixelColor(0, 0), QColor(Qt::blue));
        server.stop();
    }
    void loggerEscalationAndCallback() {
        QTemporaryDir dir;
        AppLogger::init(dir.path());
        bool callbackCalled = false;
        QString lastLevel;
        QString lastMsg;
        AppLogger::setLogCallback([&](const QString &level, const QString &msg, const QString &/*time*/) {
            callbackCalled = true;
            lastLevel = level;
            lastMsg = msg;
        });

        LOG_WARN("测试告警消息123");
        QCOMPARE(lastLevel, QStringLiteral("WARN"));
        QVERIFY(lastMsg.contains("测试告警消息123"));
        QVariantMap warnMap = AppLogger::latestWarningOrError();
        QCOMPARE(warnMap.value("level").toString(), QStringLiteral("WARN"));
        QVERIFY(warnMap.value("message").toString().contains("测试告警消息123"));

        LOG_ERROR("测试严重错误456");
        QCOMPARE(lastLevel, QStringLiteral("ERROR"));
        QVERIFY(lastMsg.contains("测试严重错误456"));
        QVariantMap errMap = AppLogger::latestWarningOrError();
        QCOMPARE(errMap.value("level").toString(), QStringLiteral("ERROR"));
        QVERIFY(errMap.value("message").toString().contains("测试严重错误456"));

        AppLogger::clearLatestWarningOrError();
        QVERIFY(AppLogger::latestWarningOrError().isEmpty());
        AppLogger::setLogCallback(nullptr);
        AppLogger::shutdown();
    }
    void tcpReceiverDisconnectsOverflowingClient() {
        TcpDataReceiver receiver;
        QVERIFY(receiver.listen(QHostAddress::LocalHost, 0));
        quint16 port = receiver.port();
        QTcpSocket client;
        client.connectToHost(QHostAddress::LocalHost, port);
        QVERIFY(client.waitForConnected(3000));
        QTRY_COMPARE(receiver.clientCount(), 1);

        // Send 2.5MB of data without any newline
        QByteArray junk(256 * 1024, 'X');
        for (int i = 0; i < 10; ++i) {
            client.write(junk);
            client.flush();
            QTest::qWait(10);
        }

        // The receiver should disconnect the overflowing client to protect system memory
        QTRY_COMPARE(receiver.clientCount(), 0);
        receiver.stop();
    }
    void tcpReceiverDropsIdleAndOversizedLines() {
        TcpDataReceiver receiver;
        receiver.setIdleTimeoutMs(300);
        receiver.batchHandler = [](const QJsonObject &, QString &) { return true; };
        QVERIFY(receiver.listen(QHostAddress::LocalHost, 0));

        // 空闲连接：超时后被断开
        QTcpSocket idle;
        idle.connectToHost(QHostAddress::LocalHost, receiver.port());
        QVERIFY(idle.waitForConnected(3000));
        QTRY_COMPARE(receiver.clientCount(), 1);
        QTRY_COMPARE_WITH_TIMEOUT(receiver.clientCount(), 0, 3000);

        // 活跃连接持续发送有效报文时不被断开
        QTcpSocket active;
        active.connectToHost(QHostAddress::LocalHost, receiver.port());
        QVERIFY(active.waitForConnected(3000));
        const QByteArray ok = R"({"carrierId":1,"wheels":[{"wheelId":1,"result":"OK","imageName":"a.png"}]})" "\n";
        for (int i = 0; i < 6; ++i) {
            active.write(ok);
            QTRY_VERIFY(active.canReadLine());
            QVERIFY(active.readLine().contains("\"OK\""));
            QTest::qWait(100);
        }
        QCOMPARE(receiver.clientCount(), 1);

        // 单条报文超过 64 KB：断开
        QByteArray huge = "{\"carrierId\":1,\"wheels\":[],\"pad\":\"" + QByteArray(70 * 1024, 'x') + "\"}\n";
        active.write(huge);
        QTRY_COMPARE(receiver.clientCount(), 0);
        receiver.stop();
    }

    void thumbnailCacheBoundsSizeAndMemory() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        const QString color = dir.filePath("large.jpg");
        QImage large(2000, 1000, QImage::Format_RGB32); large.fill(Qt::darkCyan);
        QVERIFY(large.save(color, "JPG"));
        const QString gray = dir.filePath("gray.png");
        QImage grayImage(1200, 900, QImage::Format_Grayscale8); grayImage.fill(128);
        QVERIFY(grayImage.save(gray, "PNG"));

        QCOMPARE(ThumbnailCache::edgeFor(QSize()), ThumbnailCache::kDefaultEdge);
        QCOMPARE(ThumbnailCache::edgeFor(QSize(200, 150)), 320);
        QCOMPARE(ThumbnailCache::edgeFor(QSize(5000, 100)), 640);

        // 解码直接得到缩略图尺寸；灰度图保持单通道
        const QImage thumb = ThumbnailCache::decode(color, 320);
        QCOMPARE(thumb.size(), QSize(320, 160));
        const QImage grayThumb = ThumbnailCache::decode(gray, 320);
        QCOMPARE(grayThumb.size(), QSize(320, 240));
        QCOMPARE(grayThumb.format(), QImage::Format_Grayscale8);
        QString error;
        QVERIFY(ThumbnailCache::decode(dir.filePath("missing.png"), 320, &error).isNull());
        QVERIFY(!error.isEmpty());

        // 缓存命中不重复占用；超过上限时淘汰旧缩略图
        ThumbnailCache cache(300 * 1024); // 一张 320x160 RGB32 缩略图 200KB
        QVERIFY(!cache.thumbnail(color, 320).isNull());
        QVERIFY(!cache.thumbnail(color, 320).isNull());
        QCOMPARE(cache.count(), 1);
        QVERIFY(!cache.thumbnail(color, 480).isNull());
        QVERIFY(cache.usedBytes() <= cache.maxBytes());
        QCOMPARE(cache.count(), 1);

        // 文件被覆盖后按新内容重新生成
        QTest::qWait(20);
        QImage replaced(1000, 1000, QImage::Format_RGB32); replaced.fill(Qt::red);
        QVERIFY(replaced.save(color, "JPG"));
        QCOMPARE(cache.thumbnail(color, 320).size(), QSize(320, 320));
        cache.clear();
        QCOMPARE(cache.count(), 0);
    }
};
QTEST_GUILESS_MAIN(ReleaseBoundaryTests)
#include "ReleaseBoundaryTests.moc"
