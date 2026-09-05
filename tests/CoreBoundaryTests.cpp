#include <QtTest>
#include <QSqlDatabase>
#include <QSqlQuery>

#include "AgcUtils.h"
#include "DbSchema.h"
#include "ImageListModel.h"

class CoreBoundaryTests final : public QObject
{
    Q_OBJECT

private slots:
    void modelRejectsOutOfRangeSlots()
    {
        ImageListModel model;
        ImageItem item;

        QVERIFY(!model.updateSlotItem(-1, item));
        QVERIFY(!model.updateSlotItem(ImageListModel::MaxItemCount, item));
        QCOMPARE(model.count(), 0);

        QVERIFY(model.updateSlotItem(ImageListModel::MaxItemCount - 1, item));
        QCOMPARE(model.count(), ImageListModel::MaxItemCount);
    }

    void modelRejectsOversizedReplacement()
    {
        ImageListModel model;
        QVector<ImageItem> valid(ImageListModel::MaxItemCount);
        model.setItems(valid);
        QCOMPARE(model.count(), ImageListModel::MaxItemCount);

        QVector<ImageItem> invalid(ImageListModel::MaxItemCount + 1);
        model.setItems(invalid);
        QCOMPARE(model.count(), ImageListModel::MaxItemCount);
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
                "INSERT INTO record(createtime,rackno,wheelno,result,imagename) "
                "VALUES(:time,'1','1',:result,:image)"));
            auto addRecord = [&insert](const QString &time, int result, const QString &image) {
                insert.bindValue(QStringLiteral(":time"), time);
                insert.bindValue(QStringLiteral(":result"), result);
                insert.bindValue(QStringLiteral(":image"), image);
                return insert.exec();
            };

            QVERIFY(addRecord(QStringLiteral("2026-09-04T10:00:00"), 0, QStringLiteral("new-ng.jpg")));
            QVERIFY(addRecord(QStringLiteral("2026-09-04T09:00:00"), 0, QStringLiteral("old-ng.jpg")));

            QSqlQuery alert(db);
            QVERIFY(alert.exec(QStringLiteral("SELECT imagename FROM alertrecord WHERE rackno='1' AND wheelno='1'")));
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
};

QTEST_GUILESS_MAIN(CoreBoundaryTests)
#include "CoreBoundaryTests.moc"
