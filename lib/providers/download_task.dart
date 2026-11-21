// Download task model, split out of download_provider.dart.
import 'package:olib_api_plugin/olib_api_plugin.dart';

enum DownloadStatus { pending, downloading, completed, error, cancelled }

class DownloadTask {
  final String id;
  final Book book;
  final double progress;
  final DownloadStatus status;
  final String? filePath;
  final String? error;
  final DateTime? downloadedAt;
  final int? fileSize;
  final bool needsFreshLink;
  final bool missingFile;

  /// 用户自己 Z 站账号当日下载次数已用尽导致的失败。
  final bool quotaExceeded;

  /// 该任务来自外部源解析出的直链（Anna / LibGen）或 LAN 传书，
  /// 而不是 z 站账号下载：应用被杀后无法复用旧直链，只能提示用户
  /// 回详情页重新获取链接（残片仍会被下一次下载续用）。
  final bool external;

  /// 应用被系统杀掉后从磁盘恢复出来的任务：字节还在，点重试即可
  /// 续传，不是真正的下载失败。
  final bool interrupted;

  /// 该任务的 .part 路径（恢复时用来确认字节还在），不展示。
  final String? partPath;

  bool get canRetry =>
      (status == DownloadStatus.error || status == DownloadStatus.cancelled) &&
      !needsFreshLink &&
      !missingFile &&
      book.id > 0 &&
      (book.hash?.isNotEmpty ?? false);

  const DownloadTask({
    required this.id,
    required this.book,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.filePath,
    this.error,
    this.downloadedAt,
    this.fileSize,
    this.needsFreshLink = false,
    this.missingFile = false,
    this.quotaExceeded = false,
    this.external = false,
    this.interrupted = false,
    this.partPath,
  });

  DownloadTask copyWith({
    String? id,
    Book? book,
    double? progress,
    DownloadStatus? status,
    String? filePath,
    String? error,
    DateTime? downloadedAt,
    int? fileSize,
    bool? needsFreshLink,
    bool? missingFile,
    bool? quotaExceeded,
    bool? external,
    bool? interrupted,
    String? partPath,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      book: book ?? this.book,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      error: error ?? this.error,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      fileSize: fileSize ?? this.fileSize,
      needsFreshLink: needsFreshLink ?? this.needsFreshLink,
      missingFile: missingFile ?? this.missingFile,
      quotaExceeded: quotaExceeded ?? this.quotaExceeded,
      external: external ?? this.external,
      interrupted: interrupted ?? this.interrupted,
      partPath: partPath ?? this.partPath,
    );
  }
}

/// Z 站当日下载额度已用尽。精简版仓库里此前只有引用、没有定义
///（原定义随私有插件缺失），此处按仓库内同类异常的写法补定义；
/// 用法只有无参构造与类型捕获，不携带额外字段。
class DownloadLimitReachedException implements Exception {
  const DownloadLimitReachedException();
  @override
  String toString() => 'DownloadLimitReachedException';
}
