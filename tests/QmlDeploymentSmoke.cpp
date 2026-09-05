#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickStyle>
#include <QDebug>
int main(int argc, char **argv)
{
    QQuickStyle::setStyle("Fusion");
    QGuiApplication app(argc, argv);
    if (argc != 2) return 2;
    QQmlEngine engine;
    engine.setImportPathList({QString::fromLocal8Bit(argv[1]), "qrc:/qt-project.org/imports"});
    QQmlComponent component(&engine);
    component.setData("import QtQuick\nimport QtQuick.Controls\nimport QtQuick.Layouts\nimport QtQuick.Effects\nimport QtQuick3D\nimport QtQuick3D.AssetUtils\nButton { text: 'Deployment check' }", QUrl());
    QObject *object = component.create();
    if (!object) { qCritical() << component.errors(); return 1; }
    delete object;
    qInfo() << "Packaged QML imports and Fusion Button: OK";
    return 0;
}
