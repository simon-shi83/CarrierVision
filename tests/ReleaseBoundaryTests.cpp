#include <QtTest>
#include <QTemporaryDir>
#include <QImage>
#include <QBuffer>
#include <QSqlQuery>
#include <QSqlError>
#include <QElapsedTimer>
#include "DbSchema.h"
#include "AgcUtils.h"
#include "ImageIngest.h"
#include "ArchiveMaintenance.h"
#include "FtpServer.h"
#include "AppLogger.h"

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
    static QString imageName(const QString &root) { return root + "/time_1_1_1OK_12_20_10_end.png"; }
    static bool makeImage(const QString &path, Qt::GlobalColor color = Qt::red) {
        QImage image(8,8,QImage::Format_RGB32); image.fill(color); return image.save(path,"PNG");
    }
private slots:
    void init() {
        db = QSqlDatabase::addDatabase("QSQLITE", "release-test");
        db.setDatabaseName(":memory:"); QVERIFY(db.open()); QVERIFY(DBSchema::ensureAllTables(db));
    }
    void cleanup() { db.close(); db = {}; QSqlDatabase::removeDatabase("release-test"); }
    void rejectsUnknownResultsAndOverflow() {
        ImageIngest::Metadata data; QString error;
        QVERIFY(ImageIngest::parse("t_1_1_1NG_0_2_1_end.png",data,error));
        QCOMPARE(data.wheels.first().result,0);
        QVERIFY(ImageIngest::parse("t_50_12_11OK_12NG_0_0_0_end.png",data,error));
        QCOMPARE(data.wheels.size(),2);
        QVERIFY(!ImageIngest::parse("t_1_1_1_12_20_10_end.png",data,error));
        QVERIFY(!ImageIngest::parse("t_1_1_1OK_broken_20_10_end.png",data,error));
        QVERIFY(!ImageIngest::parse("t_1_1_1OK_999999999999_20_10_end.png",data,error));
        QVERIFY(!ImageIngest::parse("t_51_1_1OK_12_20_10_end.png",data,error));
    }
    void transactionRollsBackBothWheels() {
        ImageIngest::Metadata data; QString error;
        QVERIFY(ImageIngest::parse("t_1_1_1NG_2NG_1_2_3_end.png",data,error));
        QSqlQuery q(db);
        QVERIFY(q.exec("CREATE TRIGGER fail_second BEFORE INSERT ON record WHEN NEW.wheelno='2' BEGIN SELECT RAISE(ABORT,'injected'); END"));
        bool inserted = false;
        QVERIFY(!ImageIngest::record(db,data,"test.png","2026-09-05 10:00:00",{10,10},inserted,error));
        for (const auto &table : {"record","alertrecord","rackwheelnorm"}) {
            QVERIFY(q.exec(QString("SELECT COUNT(*) FROM %1").arg(table))); QVERIFY(q.next()); QCOMPARE(q.value(0).toInt(),0);
        }
        QVERIFY(q.exec("DROP TRIGGER fail_second"));
        QVERIFY(ImageIngest::record(db,data,"test.png","2026-09-05 10:00:00",{10,10},inserted,error)); QVERIFY(inserted);
        QVERIFY(ImageIngest::record(db,data,"test.png","2026-09-05 10:00:00",{10,10},inserted,error)); QVERIFY(!inserted);
    }
    void lateNgCannotResurrectOldAlert() {
        QSqlQuery q(db);
        QVERIFY(q.exec("INSERT INTO record(createtime,rackno,wheelno,result,imagename) VALUES('2026-09-05 11:00:00','1','1',1,'new.png')"));
        QVERIFY(q.exec("INSERT INTO record(createtime,rackno,wheelno,result,imagename) VALUES('2026-09-05T10:00:00','1','1',0,'old.png')"));
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
        q.prepare("INSERT INTO record(createtime,rackno,wheelno,result,imagename) VALUES(:t,'1','1',1,:n)");
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
        QVERIFY(q.exec("INSERT INTO record(createtime,rackno,wheelno,result,imagename) VALUES('2026-09-05 11:00:00','1','1',1,'keep.png')"));
        int removed; bool more; QString error;
        QVERIFY(ArchiveMaintenance::cleanup(db,dir.path(),{dir.path()},QDateTime::fromString("2026-06-07T01:00:00",Qt::ISODate),removed,more,error));
        QVERIFY(QFile::exists(target)); QCOMPARE(removed,0);
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
        QVERIFY(command(client,"STOR time_1_1_1OK_12_20_10_end.png").startsWith("150"));
        upload.write("partial image");
        QVERIFY(command(client,"ABOR").startsWith("226"));
        QVERIFY(!QFile::exists(imageName(dir.path())));
        QVERIFY(!QFile::exists(imageName(dir.path())+".cv-pending"));
        QTRY_VERIFY(QDir(dir.path()).entryList({".cv-upload-*"},QDir::Files|QDir::Hidden).isEmpty());
        server.stop();
    }
    void ftpUploadAndCredentialRevocation() {
        QTemporaryDir dir; FtpServer server; QString error;
        server.uploadHandler = [&](const QString &staged,const QString &target) { return ImageIngest::accept(staged,target,[](const QString&){return true;},error); };
        QVERIFY(server.listen(QHostAddress::LocalHost,0,dir.path(),QMap<QString,QString>{{"u","p"}}));
        QTcpSocket client; client.connectToHost(QHostAddress::LocalHost,server.port()); QVERIFY(reply(client).startsWith("220"));
        QVERIFY(command(client,"USER u").startsWith("331")); QVERIFY(command(client,"PASS p").startsWith("230"));
        QString epsv=command(client,"EPSV"); const auto port=epsv.section('|',3,3).toUShort(); QVERIFY(port);
        QTcpSocket data; data.connectToHost(QHostAddress::LocalHost,port);
        QTRY_COMPARE(data.state(),QAbstractSocket::ConnectedState);
        auto *session = server.findChild<FtpControlConnection*>(); QVERIFY(session);
        QTRY_VERIFY(session->findChild<QTcpSocket*>());
        QCOMPARE(session->findChild<QTcpSocket*>()->readBufferSize(),qint64(256*1024));
        QVERIFY(command(client,"STOR time_1_1_1OK_12_20_10_end.png").startsWith("150"));
        QImage image(8,8,QImage::Format_RGB32); image.fill(Qt::red); QByteArray bytes; QBuffer buffer(&bytes); QVERIFY(buffer.open(QIODevice::WriteOnly)); QVERIFY(image.save(&buffer,"PNG"));
        data.write(bytes); data.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"),qPrintable(error)); QVERIFY(QFile::exists(imageName(dir.path())));
        server.setUsers({}); QTRY_COMPARE(server.clientCount(),0);
        server.stop();
    }
    void databaseDefaultsAndHelpers() {
        QCOMPARE(DBSchema::getConfigInt(db, "network/tcpPort", 0), 22345);
        QCOMPARE(DBSchema::getConfig(db, "ftp/rootDirectory", ""), QString("archive"));
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

        // verify rack_wheel_norm
        QVERIFY(q.exec("SELECT COUNT(*) FROM rack_wheel_norm"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 400); // 50 racks * 8 wheels
    }
    void defaultDatabasePathIsUnderDataDirectory() {
        QString dbPath = DBSchema::defaultDatabasePath();
        QVERIFY(dbPath.endsWith("data/dataAgc.db") || dbPath.endsWith("data\\dataAgc.db"));
    }
    void rackWheelNormDatabaseOperations() {
        QSqlQuery q(db);
        q.prepare("UPDATE rack_wheel_norm SET standard_distance = 150 WHERE rackno = 5 AND wheelno = 3");
        QVERIFY(q.exec());

        q.prepare("SELECT standard_distance FROM rack_wheel_norm WHERE rackno = 5 AND wheelno = 3");
        QVERIFY(q.exec());
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 150);

        q.prepare("SELECT standard_distance FROM rack_wheel_norm WHERE rackno = 5 AND wheelno = 4");
        QVERIFY(q.exec());
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toInt(), 0);
    }
    void recordBatchAndRoundPersistence() {
        ImageIngest::Metadata data; QString error;
        QVERIFY(ImageIngest::parse("t_1_1_1OK_12_20_10_end.png", data, error));
        bool inserted = false;
        QVERIFY(ImageIngest::record(db, data, "batch_test.png", "2026-09-05 12:00:00", {10, 10}, inserted, error, "BATCH_R1_R2", 2));
        QVERIFY(inserted);

        QSqlQuery q(db);
        QVERIFY(q.exec("SELECT batch_id, round_no FROM record WHERE imagename = 'batch_test.png'"));
        QVERIFY(q.next());
        QCOMPARE(q.value(0).toString(), QString("BATCH_R1_R2"));
        QCOMPARE(q.value(1).toInt(), 2);

        // verify index exists
        QVERIFY(q.exec("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_record_batch'"));
        QVERIFY(q.next());
    }
    void timestampAndCollisionParsing() {
        const QDateTime dt = ImageIngest::parseTimestamp("20260905143000_1_1_1OK_10_20_10_end.png");
        QCOMPARE(dt.toString("yyyy-MM-dd HH:mm:ss"), QString("2026-09-05 14:30:00"));

        const QDateTime fallback(QDate(2026, 1, 1), QTime(0, 0, 0));
        QCOMPARE(ImageIngest::parseTimestamp("no_date_1_1_1OK_end.png", fallback), fallback);

        ImageIngest::Metadata data; QString error;
        QVERIFY(ImageIngest::parse("t_1_1_1NG_0_2_1_end_v2.png", data, error));
        QCOMPARE(data.rack, 1);
        QCOMPARE(data.camera, 1);
        QCOMPARE(data.wheels.size(), 1);

        QVERIFY(ImageIngest::parse("t_50_12_11OK_12NG_0_0_0_end_v3.png", data, error));
        QCOMPARE(data.rack, 50);
        QCOMPARE(data.camera, 12);
        QCOMPARE(data.wheels.size(), 2);
    }
    void collisionSafeFtpUpload() {
        QTemporaryDir dir; FtpServer server; QString error;
        server.uploadHandler = [&](const QString &staged, const QString &target) {
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
        QVERIFY(command(client, "STOR t_1_1_1OK_12_20_10_end.png").startsWith("150"));
        QImage redImg(8, 8, QImage::Format_RGB32); redImg.fill(Qt::red);
        QByteArray redBytes; QBuffer buf1(&redBytes); buf1.open(QIODevice::WriteOnly); redImg.save(&buf1, "PNG");
        data1.write(redBytes); data1.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"), qPrintable(error));
        const QString path1 = dir.filePath("t_1_1_1OK_12_20_10_end.png");
        QVERIFY(QFile::exists(path1));

        // Second upload with same name but different content: blue image
        epsv = command(client, "EPSV");
        QTcpSocket data2; data2.connectToHost(QHostAddress::LocalHost, epsv.section('|', 3, 3).toUShort());
        QTRY_COMPARE(data2.state(), QAbstractSocket::ConnectedState);
        QVERIFY(command(client, "STOR t_1_1_1OK_12_20_10_end.png").startsWith("150"));
        QImage blueImg(8, 8, QImage::Format_RGB32); blueImg.fill(Qt::blue);
        QByteArray blueBytes; QBuffer buf2(&blueBytes); buf2.open(QIODevice::WriteOnly); blueImg.save(&buf2, "PNG");
        data2.write(blueBytes); data2.disconnectFromHost();
        QVERIFY2(reply(client).startsWith("226"), qPrintable(error));

        // Both original and version-suffixed files must exist without data loss
        const QString path2 = dir.filePath("t_1_1_1OK_12_20_10_end_v2.png");
        QVERIFY(QFile::exists(path1));
        QVERIFY(QFile::exists(path2));
        QCOMPARE(QImage(path1).pixelColor(0, 0), QColor(Qt::red));
        QCOMPARE(QImage(path2).pixelColor(0, 0), QColor(Qt::blue));
        server.stop();
    }
};
QTEST_GUILESS_MAIN(ReleaseBoundaryTests)
#include "ReleaseBoundaryTests.moc"
