#include "common/ImageExport.h"

#include "common/AgcUtils.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QSaveFile>
#include <QUrl>

namespace ImageExport {

namespace {

bool sameFile(const QString &a, const QString &b)
{
    const QString ca = QFileInfo(a).canonicalFilePath();
    const QString cb = QFileInfo(b).canonicalFilePath();
    if (!ca.isEmpty() && !cb.isEmpty()) return ca.compare(cb, Qt::CaseInsensitive) == 0;
    return QDir::cleanPath(QFileInfo(a).absoluteFilePath())
               .compare(QDir::cleanPath(QFileInfo(b).absoluteFilePath()), Qt::CaseInsensitive) == 0;
}

QString normalizedSuffix(const QString &suffix)
{
    const QString s = suffix.toLower();
    if (s == QLatin1String("jpeg")) return QStringLiteral("jpg");
    if (s == QLatin1String("tif")) return QStringLiteral("tiff");
    return s;
}

bool copyBytes(const QString &source, const QString &target, QString *error)
{
    QFile in(source);
    if (!in.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("无法读取原图：%1").arg(in.errorString());
        return false;
    }
    QSaveFile out(target);
    if (!out.open(QIODevice::WriteOnly)) {
        *error = QStringLiteral("无法写入目标文件：%1").arg(out.errorString());
        return false;
    }
    constexpr qint64 chunk = 4 * 1024 * 1024; // 大图可达数百 MB，分块复制避免一次性占用内存
    QByteArray buffer;
    while (!in.atEnd()) {
        buffer = in.read(chunk);
        if (buffer.isEmpty() && in.error() != QFileDevice::NoError) {
            out.cancelWriting();
            *error = QStringLiteral("读取原图中断：%1").arg(in.errorString());
            return false;
        }
        if (out.write(buffer) != buffer.size()) {
            out.cancelWriting();
            *error = QStringLiteral("写入目标文件失败：%1").arg(out.errorString());
            return false;
        }
    }
    if (!out.commit()) {
        *error = QStringLiteral("提交目标文件失败：%1").arg(out.errorString());
        return false;
    }
    return true;
}

bool transcode(const QString &source, const QString &target, const QString &suffix, QString *error)
{
    QImageReader reader(source);
    reader.setAutoTransform(false); // 与界面显示和原图像素保持一致
    reader.setAllocationLimit(0);   // 工业相机原图常超过默认 256 MB 解码上限
    const QImage image = reader.read();
    if (image.isNull()) {
        *error = QStringLiteral("原图解码失败：%1").arg(reader.errorString());
        return false;
    }
    QSaveFile out(target);
    if (!out.open(QIODevice::WriteOnly)) {
        *error = QStringLiteral("无法写入目标文件：%1").arg(out.errorString());
        return false;
    }
    QImageWriter writer(&out, suffix.toLatin1());
    if (suffix == QLatin1String("jpg")) writer.setQuality(95);
    if (!writer.write(image)) {
        out.cancelWriting();
        *error = QStringLiteral("按 %1 格式编码失败：%2").arg(suffix.toUpper(), writer.errorString());
        return false;
    }
    if (!out.commit()) {
        *error = QStringLiteral("提交目标文件失败：%1").arg(out.errorString());
        return false;
    }
    return true;
}

} // namespace

QString localPathFromSource(const QString &source)
{
    const QString text = source.trimmed();
    if (text.isEmpty()) return {};
    // Windows 盘符路径（C:/... 或 C:\...）不能交给 QUrl，否则盘符会被当成协议
    if (text.size() >= 2 && text.at(1) == u':' && text.at(0).isLetter()
        && (text.size() == 2 || text.at(2) == u'/' || text.at(2) == u'\\')) {
        QString path = text;
        path.replace(u'\\', u'/');
        return QDir::cleanPath(path);
    }
    const QUrl url(text);
    if (url.isLocalFile()) return QDir::cleanPath(url.toLocalFile());
    if (!url.scheme().isEmpty()) return {};
    return AgcUtils::resolveAppPath(text);
}

QVariantMap probe(const QString &source)
{
    QVariantMap info;
    const QString path = localPathFromSource(source);
    const QFileInfo fi(path);
    info.insert(QStringLiteral("exists"), !path.isEmpty() && fi.isFile());
    info.insert(QStringLiteral("fileName"), fi.fileName());
    info.insert(QStringLiteral("suffix"), fi.suffix().toLower());
    if (path.isEmpty() || !fi.isFile()) return info;
    info.insert(QStringLiteral("bytes"), fi.size());
    QImageReader reader(path);
    const QSize size = reader.size();
    info.insert(QStringLiteral("width"), size.isValid() ? size.width() : 0);
    info.insert(QStringLiteral("height"), size.isValid() ? size.height() : 0);
    info.insert(QStringLiteral("format"), QString::fromLatin1(reader.format()).toUpper());
    return info;
}

QStringList supportedTargetSuffixes(const QString &sourceSuffix)
{
    QStringList result;
    const QString original = normalizedSuffix(sourceSuffix);
    if (!original.isEmpty()) result << original;
    const QList<QByteArray> writable = QImageWriter::supportedImageFormats();
    for (const char *candidate : {"png", "jpg", "bmp", "tiff"}) {
        const QString s = QString::fromLatin1(candidate);
        if (result.contains(s)) continue;
        if (writable.contains(QByteArray(candidate))) result << s;
    }
    return result;
}

Result exportImage(const QString &source, const QString &target)
{
    Result result;
    const QString sourcePath = localPathFromSource(source);
    if (sourcePath.isEmpty() || !QFileInfo(sourcePath).isFile()) {
        result.message = QStringLiteral("原图文件不存在或已被清理");
        return result;
    }
    QString targetPath = localPathFromSource(target);
    if (targetPath.isEmpty() || !QFileInfo(targetPath).isAbsolute()) {
        result.message = QStringLiteral("保存位置无效");
        return result;
    }
    const QFileInfo sourceInfo(sourcePath);
    QFileInfo targetInfo(targetPath);
    if (targetInfo.suffix().isEmpty() && !sourceInfo.suffix().isEmpty()) {
        targetPath += u'.' + sourceInfo.suffix();
        targetInfo = QFileInfo(targetPath);
    }
    if (targetInfo.fileName().isEmpty()) {
        result.message = QStringLiteral("请填写文件名");
        return result;
    }
    if (sameFile(sourcePath, targetPath)) {
        result.message = QStringLiteral("不能覆盖原图，请换一个位置或文件名");
        return result;
    }
    if (!QDir().mkpath(targetInfo.absolutePath())) {
        result.message = QStringLiteral("无法创建目标文件夹");
        return result;
    }

    const QString srcSuffix = normalizedSuffix(sourceInfo.suffix());
    const QString dstSuffix = normalizedSuffix(targetInfo.suffix());
    QString error;
    bool ok = false;
    if (dstSuffix == srcSuffix) {
        ok = copyBytes(sourcePath, targetPath, &error);
    } else if (!supportedTargetSuffixes(QString()).contains(dstSuffix)) {
        error = QStringLiteral("不支持保存为 .%1 格式").arg(targetInfo.suffix());
    } else {
        ok = transcode(sourcePath, targetPath, dstSuffix, &error);
    }
    result.ok = ok;
    result.targetPath = QDir::toNativeSeparators(targetInfo.absoluteFilePath());
    result.message = ok ? QStringLiteral("已保存到 %1").arg(result.targetPath) : error;
    return result;
}

} // namespace ImageExport
