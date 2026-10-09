import 'dart:convert';

import '../models/radio_station.dart';
import '../utils/log.dart';

class CustomStationsImportResult {
  const CustomStationsImportResult({
    required this.stations,
    required this.added,
    required this.skipped,
    this.malformed = 0,
  });

  final List<RadioStation> stations;
  final int added;
  final int skipped;

  /// 解析时因类型不对被跳过的条目数。
  ///
  /// 用户手改的备份里出现 `"id": 123` 这类值很常见。原先一条这种记录就会
  /// 抛异常、冒泡到 decode 的 catch，把**整份**列表丢掉 —— 用户只看到一句
  /// 「没有可导入的电台 JSON」，完全不知道是第几条出的问题。
  final int malformed;
}

/// 手动电台 JSON 备份：剪贴板导入导出。
abstract final class CustomStationsBackup {
  static String encode(List<RadioStation> stations) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(stations.map((s) => s.toJson()).toList());
  }

  static List<RadioStation>? decode(
    String raw, {
    void Function(int malformed)? onMalformed,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return null;
      // 逐条容错：一条坏记录（多半是用户手改过，值类型对不上）只丢它自己，
      // 不能连带把整份备份判成「文件坏了」。
      final stations = <RadioStation>[];
      var malformed = 0;
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        try {
          final station = RadioStation.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (station.name.trim().isEmpty || station.streamUrl.trim().isEmpty) {
            continue;
          }
          stations.add(
            station.copyWith(
              source: StationSource.custom,
              tags:
                  {
                    '自定义',
                    ...station.tags.where((t) => t.trim().isNotEmpty),
                  }.toList(),
            ),
          );
        } catch (error, stackTrace) {
          malformed += 1;
          AppLog.e(
            'CustomStations',
            'skip malformed record',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      // 总是上报真实条数（含 0）：调用方要靠它决定怎么提示，
      // 只在 >0 时回调的话，调用方拿到的是「没回调」而非「0 条」。
      onMalformed?.call(malformed);
      return stations.isEmpty ? null : stations;
    } catch (error, stackTrace) {
      AppLog.e(
        'CustomStations',
        'decode failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static CustomStationsImportResult merge({
    required List<RadioStation> existing,
    required List<RadioStation> incoming,
    int malformed = 0,
  }) {
    final merged = List<RadioStation>.from(existing);
    var added = 0;
    var skipped = 0;
    for (final station in incoming) {
      final conflict = RadioStation.duplicateReason(
        name: station.name,
        streamUrl: station.streamUrl,
        existing: merged,
      );
      if (conflict != null) {
        skipped++;
        continue;
      }
      merged.add(
        station.copyWith(
          id: 'user-${DateTime.now().microsecondsSinceEpoch}-$added',
          source: StationSource.custom,
        ),
      );
      added++;
    }
    return CustomStationsImportResult(
      stations: merged,
      added: added,
      skipped: skipped,
      malformed: malformed,
    );
  }
}
