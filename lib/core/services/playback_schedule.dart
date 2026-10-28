import 'playback_converter.dart';

/// A boundary may stop short notes while longer voices remain sounding.
class PlaybackFrame {
  PlaybackFrame({
    required this.timeMs,
    required Iterable<int> starts,
    required Iterable<int> stops,
  }) : starts = List.unmodifiable(starts),
       stops = List.unmodifiable(stops);
  final int timeMs;
  final List<int> starts, stops;
}

class PlaybackSchedule {
  PlaybackSchedule(
    List<PlaybackEvent> events, {
    required int endMs,
    Iterable<int> boundaries = const [],
  }) : events = List.unmodifiable(events) {
    final starts = <int, List<int>>{}, stops = <int, List<int>>{};
    final times = <int>{0, endMs, ...boundaries};
    for (final (i, event) in events.indexed) {
      starts.putIfAbsent(event.baseOnsetMs, () => []).add(i);
      stops.putIfAbsent(event.baseEndMs, () => []).add(i);
      times.addAll([event.baseOnsetMs, event.baseEndMs]);
    }
    final ordered = times.toList()..sort();
    frames = List.unmodifiable(
      ordered.map(
        (t) => PlaybackFrame(
          timeMs: t,
          starts: starts[t] ?? const [],
          stops: stops[t] ?? const [],
        ),
      ),
    );
  }
  final List<PlaybackEvent> events;
  late final List<PlaybackFrame> frames;

  int frameAt(int timeMs) {
    final i = frames.indexWhere((f) => f.timeMs >= timeMs);
    return i < 0 ? frames.length - 1 : i;
  }

  List<int> activeAt(int timeMs) => [
    for (final (i, event) in events.indexed)
      if (event.baseOnsetMs <= timeMs && event.baseEndMs > timeMs) i,
  ];

  int? primaryAt(int timeMs, int focusPart) {
    final active = activeAt(timeMs);
    return active.where((i) => events[i].partIndex == focusPart).firstOrNull ??
        active.firstOrNull ??
        events.indexed
            .where((e) => e.$2.baseOnsetMs > timeMs)
            .map((e) => e.$1)
            .firstOrNull;
  }
}
