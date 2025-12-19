import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter/foundation.dart';

/// ChatCallKit 日志工具类
/// 功能：1. 控制台输出日志 2. 日志写入本地文件 3. 自动清理旧日志（防堆积）
class ChatCallKitLogger {
  // 开关：是否开启日志（控制台+文件）
  static bool enableLog = true;

  // 日志文件配置
  static const String _logFilePrefix = 'chatcallkit'; // 日志文件前缀（便于区分）
  static const int _maxFileSize = 10 * 1024 * 1024; // 单日志文件最大大小（10MB）
  static const int _maxLogFileCount = 10; // 最多保留的日志文件数量
  static const int _maxLogRetentionDays = 7; // 日志文件最长保留天数

  // 单例模式（避免重复创建文件句柄）
  ChatCallKitLogger._();
  static final ChatCallKitLogger instance = ChatCallKitLogger._();

  // 互斥锁（防止并发写入冲突）
  Future<void>? _currentWriteOperation;

  /// 核心日志方法：输出到控制台 + 写入文件
  /// [content] 日志内容
  /// [tag] 日志标签（可选，便于分类）
  Future<void> log(String content, {String tag = 'debug'}) async {
    if (!enableLog) return;

    // 1. 输出到控制台（带标签，便于筛选）
    final String consoleLog = '[$tag] $content';
    developer.log(consoleLog, name: 'ChatCallKit');

    // 2. 使用互斥锁写入文件（防止并发冲突）
    await _lockAndWrite(content, tag: tag);
  }

  /// 内部方法：使用互斥锁执行写入操作
  Future<void> _lockAndWrite(String content, {required String tag}) async {
    // 等待之前的写入操作完成
    while (_currentWriteOperation != null) {
      try {
        await _currentWriteOperation;
      } catch (_) {
        // 忽略之前操作的错误
      }
    }

    // 开始新的写入操作
    final completer = Completer<void>();
    _currentWriteOperation = completer.future;

    try {
      await _writeLogToFile(content, tag: tag);
      completer.complete();
    } catch (e, stack) {
      developer.log(
        '日志写入文件失败：$e\n堆栈：$stack',
        name: 'ChatCallKit-FileError',
      );
      completer.completeError(e, stack);
    } finally {
      _currentWriteOperation = null;
    }
  }

  /// 内部方法：将日志写入文件
  Future<void> _writeLogToFile(String content, {required String tag}) async {
    // Web 平台无本地文件系统，直接返回
    if (kIsWeb) return;

    // 获取当前要写入的主日志文件
    final File logFile = await _getMainLogFile();

    // 检查文件大小，超限则归档旧文件
    if (await _isFileExceedMaxSize(logFile)) {
      await _archiveOldLogFile(logFile);
      // 归档后立即清理旧文件（二选一：按数量/按时间）
      await _cleanOldLogsByCount();
      // await _cleanOldLogsByTime();
    }

    // 拼接日志内容（时间戳 + 标签 + 内容）
    final String logWithMeta = '[${_formatDateTime(DateTime.now())}] [$tag] $content\n';

    // 使用 RandomAccessFile 追加写入并立即刷新到磁盘
    RandomAccessFile? raf;
    try {
      raf = await logFile.open(mode: FileMode.append);
      // 写入数据
      await raf.writeString(logWithMeta, encoding: utf8);
      // 立即刷新到磁盘（确保数据不丢失）
      await raf.flush();
    } finally {
      // 确保文件关闭
      await raf?.close();
    }
  }

  /// 内部方法：获取主日志文件（按日期命名，每天一个）
  Future<File> _getMainLogFile() async {
    // 获取应用私有存储目录（Android/iOS 兼容）
    // Android: /data/data/包名/app_flutter/
    // iOS: /Library/Application Support/
    final Directory appDir = await getApplicationSupportDirectory();

    // 确保目录存在（递归创建）
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    // 按日期生成主日志文件名（格式：20251218_chatcallkit.log）
    final String dateStr = DateTime.now().toString().split(' ')[0].replaceAll('-', '');
    final String logFileName = '${dateStr}_$_logFilePrefix.log';
    final File logFile = File('${appDir.path}/$logFileName');

    // 文件不存在则创建空文件
    if (!await logFile.exists()) {
      await logFile.create();
    }

    return logFile;
  }

  /// 内部方法：检查文件是否超过最大大小
  Future<bool> _isFileExceedMaxSize(File file) async {
    if (!await file.exists()) return false;
    final int fileSize = await file.length();
    return fileSize > _maxFileSize;
  }

  /// 内部方法：归档旧日志文件（重命名，加时间戳）
  Future<void> _archiveOldLogFile(File oldFile) async {
    // 生成归档文件名（格式：20251218_chatcallkit_1734567890123.log）
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String newFilePath = oldFile.path.replaceFirst(
      '.log',
      '_$timestamp.log',
    );

    // 重命名旧文件（归档）
    await oldFile.rename(newFilePath);
    developer.log('归档旧日志文件：${oldFile.path} → $newFilePath', name: 'ChatCallKit-Archive');
  }

  /// 内部方法：按文件数量清理旧日志（只保留最新的 N 个）
  Future<void> _cleanOldLogsByCount() async {
    final Directory appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) return;

    // 获取当前主日志文件路径（排除，不清理）
    final File mainLogFile = await _getMainLogFile();
    final String mainLogPath = mainLogFile.path;

    // 正则：精准匹配日志文件（格式：数字日期_chatcallkit(_数字时间戳).log）
    final RegExp logFileReg = RegExp(
      r'^\d+_' + _logFilePrefix + r'(_\d+)?\.log$',
      caseSensitive: false,
    );

    // 筛选所有需要清理的旧日志文件
    final List<File> oldLogFiles = await appDir.list()
        .where((entity) =>
            entity is File &&
            // 只匹配文件名（避免路径干扰）
            logFileReg.hasMatch(Path.basename(entity.path)) &&
            // 排除正在写入的主文件
            entity.path != mainLogPath)
        .cast<File>()
        .toList();

    // 按文件修改时间排序（旧的在前，新的在后）
    oldLogFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

    // 清理超出数量的旧文件
    while (oldLogFiles.length > _maxLogFileCount) {
      final File oldestFile = oldLogFiles.first;
      try {
        await oldestFile.delete();
        developer.log('清理旧日志文件：${oldestFile.path}', name: 'ChatCallKit-Clean');
      } catch (e) {
        developer.log('清理旧日志失败：$e', name: 'ChatCallKit-CleanError');
      }
      oldLogFiles.removeAt(0);
    }
  }

  /// 内部方法：按时间清理旧日志（删除超过 N 天的文件）
  Future<void> _cleanOldLogsByTime() async {
    final Directory appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) return;

    // 获取当前主日志文件路径（排除）
    final File mainLogFile = await _getMainLogFile();
    final String mainLogPath = mainLogFile.path;

    // 计算过期时间（当前时间 - 保留天数）
    final DateTime expireTime = DateTime.now().subtract(Duration(days: _maxLogRetentionDays));

    // 正则匹配日志文件
    final RegExp logFileReg = RegExp(
      r'^\d+_' + _logFilePrefix + r'(_\d+)?\.log$',
      caseSensitive: false,
    );

    // 遍历目录，清理过期文件
    await for (final FileSystemEntity entity in appDir.list()) {
      if (entity is File &&
          logFileReg.hasMatch(Path.basename(entity.path)) &&
          entity.path != mainLogPath) {
        final DateTime lastModified = await entity.lastModified();
        if (lastModified.isBefore(expireTime)) {
          try {
            await entity.delete();
            developer.log('清理过期日志：${entity.path}', name: 'ChatCallKit-Clean');
          } catch (e) {
            developer.log('清理过期日志失败：$e', name: 'ChatCallKit-CleanError');
          }
        }
      }
    }
  }

  /// 辅助方法：格式化时间（便于日志阅读）
  String _formatDateTime(DateTime dateTime) {
    return dateTime.toString().replaceAll(' ', 'T').substring(0, 23);
  }

  /// 对外方法：获取当前日志文件路径（便于调试/导出）
  Future<String> getCurrentLogFilePath() async {
    final File logFile = await _getMainLogFile();
    return logFile.path;
  }

  /// 对外方法：手动清理所有旧日志（按需调用）
  Future<void> cleanAllOldLogs() async {
    await _cleanOldLogsByCount();
    await _cleanOldLogsByTime();
  }
}