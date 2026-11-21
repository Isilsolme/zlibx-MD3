// Downloads provider. The models live in download_task.dart, the tab
// structure in download_list_structure.dart, and the notifier's larger
// method clusters in the part files below. Dart cannot split one class
// body across parts, so each part declares a private mixin applied to
// DownloadNotifier; the public API stays on the notifier itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import '../services/hive_service.dart';
import '../services/http_client.dart';
import '../services/media_store.dart';
import '../services/pending_uri_writer.dart';
import '../services/resumable_downloader.dart';
import '../services/storage_service.dart';
import '../utils/app_log.dart';
import '../utils/diagnostics.dart';
import '../utils/file_utils.dart';
import 'download_task.dart';
import 'zlibrary_provider.dart';

export 'download_task.dart';
export 'download_list_structure.dart';

part 'download_paths.dart';
part 'download_engine.dart';
part 'download_history.dart';

/// Shared state and small helpers for the DownloadNotifier mixins below.
/// `ref` is deliberately not cached in a `late final` field: ref.invalidate
/// re-runs build() on the same notifier instance.
abstract class _DownloadNotifierBase extends Notifier<List<DownloadTask>> {
  // Getters, not `late final` fields: ref.invalidate (account switch,
  // line change, logout) re-runs build() on the SAME notifier instance,
  // and a second assignment to a late final throws LateInitializationError
  // — the same trap that blanked the library screen in SavedBooksNotifier.
  ZLibraryApi get _api => ref.read(zlibraryApiProvider);
  StorageService get _storage => ref.read(storageServiceProvider);
  final Map<String, CancelToken> _cancelTokens = {};

  /// Throttle for progress ticks: Dio can fire dozens of callbacks per
  /// second, and every publish rebuilds the whole task list for every
  /// listener. A tick is published only when progress moved >= 1% or
  /// >= 200 ms passed since the last publish for that task. Terminal
  /// transitions (completed / error / cancelled) never go through here,
  /// so they are always published immediately.
  final Map<String, double> _lastPublishedProgress = {};
  final Map<String, DateTime> _lastPublishedAt = {};

  // Not final: build() re-assigns it on every invalidate (nothing reads
  // it today; kept for the startup-history signal).
  late Future<void> ready;

  /// In-flight tasks, persisted to Hive so a process kill can be recovered
  /// on the next launch. Completed tasks are excluded (history owns them).
  static const String _activeTasksKey = 'download_tasks';
  DateTime? _lastPersistAt;

  /// Persist at most once a second: progress ticks are already throttled,
  /// but a long download still produces hundreds of them and each write
  /// serializes the whole task list.
  void _persistSoon() {
    final now = DateTime.now();
    final last = _lastPersistAt;
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _lastPersistAt = now;
    unawaited(_persistActiveTasks());
  }

  Future<void> _persistActiveTasks() async {
    try {
      final payload = <String, dynamic>{
        for (final task in state)
          if (task.status != DownloadStatus.completed && task.partPath != null)
            task.id: <String, dynamic>{
              'book': task.book.toJson(),
              'partPath': task.partPath,
              'progress': task.progress,
              'external': task.external,
            },
      };
      await HiveService.settingsBox.put(_activeTasksKey, jsonEncode(payload));
    } catch (error) {
      logIgnored('download_tasks_persist', error);
    }
  }

  /// Cancel a download
  void cancelDownload(String id) {
    final token = _cancelTokens[id];
    if (token == null) return;
    token.cancel();
    _updateTask(id, (t) => t.copyWith(status: DownloadStatus.cancelled));
    _clearProgressThrottle(id);
  }

  void markMissingFile(String id) {
    _updateTask(
      id,
      (task) => task.copyWith(
        status: DownloadStatus.error,
        missingFile: true,
        error: 'File not found',
      ),
    );
  }

  /// Remove task and delete file
  Future<void> removeTask(String id) async {
    cancelDownload(id);
    // Idempotent delete: the task may already be gone (double tap on the
    // menu, history cleanup racing the UI). A missing task used to throw
    // and the caller showed "删除失败" for a perfectly successful delete.
    final matches = state.where((t) => t.id == id).toList();
    if (matches.isEmpty) return;
    final task = matches.first;

    // Delete file if exists (content:// URIs via ContentResolver).
    if (task.filePath != null) {
      await MediaStoreFiles.delete(task.filePath!);
    }

    // Remove from persistent storage
    await _storage.removeFromDownloadHistory(id);

    // Remove from state
    state = state.where((t) => t.id != id).toList();
    _clearProgressThrottle(id);
    _lastPersistAt = null;
    _persistSoon();
  }

  /// Rebuilds tasks whose bytes survived a process kill. A record is only
  /// resurrected when its .part file (or a MediaStore pending sidecar)
  /// still exists; otherwise it is dropped. External-source tasks cannot
  /// reuse their old direct link and are marked needsFreshLink — the
  /// bytes still resume when the user downloads the book again.
  Future<void> _restoreInterruptedTasks() async {
    try {
      final raw = HiveService.settingsBox.get(_activeTasksKey);
      if (raw is! String || raw.isEmpty) return;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        await HiveService.settingsBox.delete(_activeTasksKey);
        return;
      }
      if (decoded is! Map) return;

      final restored = <DownloadTask>[];
      for (final value in decoded.values) {
        if (value is! Map) continue;
        final bookJson = value['book'];
        final partPath = value['partPath'];
        if (bookJson is! Map || partPath is! String || partPath.isEmpty) {
          continue;
        }
        final hasBytes =
            await File(partPath).exists() ||
            await File(PendingUriWriter.statePathFor(partPath)).exists();
        if (!hasBytes) continue;
        try {
          final book = Book.fromJson(Map<String, dynamic>.from(bookJson));
          final external = value['external'] == true;
          restored.add(
            DownloadTask(
              id: book.id.toString(),
              book: book,
              progress: (value['progress'] as num?)?.toDouble() ?? 0,
              status: DownloadStatus.error,
              interrupted: true,
              external: external,
              needsFreshLink: external,
              partPath: partPath,
            ),
          );
        } catch (error) {
          logIgnored('download_task_restore', error);
        }
      }
      if (restored.isEmpty) {
        await HiveService.settingsBox.delete(_activeTasksKey);
        return;
      }
      final existing = state.map((t) => t.id).toSet();
      final fresh = restored.where((t) => !existing.contains(t.id)).toList();
      if (fresh.isNotEmpty) state = [...state, ...fresh];
      _lastPersistAt = null;
      await _persistActiveTasks();
    } catch (error) {
      logIgnored('download_tasks_restore', error);
    }
  }

  void _updateOrAddTask(DownloadTask task) {
    if (state.any((t) => t.id == task.id)) {
      state = state.map((t) => t.id == task.id ? task : t).toList();
    } else {
      state = [...state, task];
    }
    _persistSoon();
  }

  /// Publishes one progress tick, throttled: a tick below 1.0 is only
  /// published when progress moved >= 1% since the last publish for
  /// this task, or >= 200 ms passed. A tick that reaches 1.0 always
  /// goes through immediately.
  void _updateProgress(String id, double progress) {
    // Late ticks from a cancelled/finished download must not republish
    // state: cancelDownload already flipped the status and cleared the
    // throttle maps, but chunks already queued in the stream keep
    // arriving for a moment.
    final token = _cancelTokens[id];
    if (token == null || token.isCancelled) return;
    // No firstOrNull dependency: avoid pulling in package:collection.
    DownloadTask? task;
    for (final t in state) {
      if (t.id == id) {
        task = t;
        break;
      }
    }
    if (task == null ||
        (task.status != DownloadStatus.downloading &&
            task.status != DownloadStatus.pending)) {
      return;
    }
    if (progress < 1.0) {
      final now = DateTime.now();
      final last = _lastPublishedProgress[id];
      final lastAt = _lastPublishedAt[id];
      if (last != null &&
          (progress - last).abs() < 0.01 &&
          lastAt != null &&
          now.difference(lastAt).inMilliseconds < 200) {
        return;
      }
      _lastPublishedProgress[id] = progress;
      _lastPublishedAt[id] = now;
    }
    _updateTask(id, (t) => t.copyWith(progress: progress));
  }

  /// Drops the throttle bookkeeping for [id]; called when a task leaves
  /// the downloading state so the maps stay bounded.
  void _clearProgressThrottle(String id) {
    _lastPublishedProgress.remove(id);
    _lastPublishedAt.remove(id);
  }

  void _updateTask(String id, DownloadTask Function(DownloadTask) updater) {
    state = state.map((t) {
      if (t.id == id) {
        return updater(t);
      }
      return t;
    }).toList();
    _persistSoon();
  }
}

class DownloadNotifier extends _DownloadNotifierBase
    with _DownloadPathsMixin, _DownloadEngineMixin, _DownloadHistoryMixin {
  @override
  List<DownloadTask> build() {
    // Load persisted download history on initialization
    ready = _loadDownloadHistory().then((_) => _restoreInterruptedTasks());
    return [];
  }
}

final downloadProvider = NotifierProvider<DownloadNotifier, List<DownloadTask>>(
  DownloadNotifier.new,
);

/// One download task by id. Watching this instead of [downloadProvider]
/// rebuilds a widget only when ITS task changes: [_updateTask] keeps the
/// identity of every untouched task, so `select` sees no change for them.
/// Use it in per-book widgets (action bars, list tiles) so one progress
/// tick no longer rebuilds every listener of the whole list.
final downloadTaskProvider = Provider.autoDispose.family<DownloadTask?, String>(
  (ref, id) {
    return ref.watch(
      downloadProvider.select((tasks) {
        for (final t in tasks) {
          if (t.id == id) return t;
        }
        return null;
      }),
    );
  },
);
