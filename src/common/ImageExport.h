#pragma once

#include <QString>
#include <QVariantMap>

// 放大窗口“另存为”：把客户端上传的原图另存到操作员选定的位置。
// 只复制或转码已入库的原图文件，不改动图像目录中的任何文件。
namespace ImageExport {

struct Result {
    bool ok = false;
    QString message;    // 面向操作员的中文提示
    QString targetPath; // 实际写入的绝对路径（成功时有效）
};

// 把 QML 传来的图像地址（file:/// URL、Windows 盘符路径或相对程序目录的路径）解析为本地绝对路径；
// 无法解析为本地文件（如 qrc、http、image://）时返回空串
QString localPathFromSource(const QString &source);

// 读取图像头信息（不解码像素）：exists、fileName、width、height、bytes、format
QVariantMap probe(const QString &source);

// 另存图像。目标扩展名与原图相同（或目标未写扩展名）时按字节原样复制，保证与原图完全一致；
// 扩展名不同时解码后按目标格式重新编码。目标写入经 QSaveFile 原子提交，失败不会留下半个文件。
Result exportImage(const QString &source, const QString &target);

// 文件对话框可选的格式（小写扩展名，不含点），第一项为原图格式
QStringList supportedTargetSuffixes(const QString &sourceSuffix);

} // namespace ImageExport
