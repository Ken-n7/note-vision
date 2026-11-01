import '../models/score.dart';
import '../models/part_playback.dart';

/// One strip per linked instrument; scanned lines share a single strip.
class PlaybackStrip {
  const PlaybackStrip(this.parts, this.name, this.settings);
  final List<int> parts;
  final String name;
  final PartPlayback settings;
}

List<PlaybackStrip> playbackStrips(Score score) {
  if (score.parts.isEmpty) return const [];
  if (score.playbackLayout == ScorePlaybackLayout.sequentialStaves) {
    return [
      PlaybackStrip(
        [for (var p = 0; p < score.parts.length; p++) p],
        score.parts.first.name,
        score.parts.first.playback,
      ),
    ];
  }
  final groups = <List<int>>[];
  for (final (p, part) in score.parts.indexed) {
    if (part.joinsPrevious && groups.isNotEmpty) {
      groups.last.add(p);
    } else {
      groups.add([p]);
    }
  }
  return [
    for (final parts in groups)
      PlaybackStrip(
        parts,
        score.parts[parts.first].name,
        score.parts[parts.first].playback,
      ),
  ];
}

/// Isolated MIDI channels prevent equal pitches in different instruments
/// from sharing note-off counts. Channel 10 is reserved for percussion.
class PlaybackMix {
  PlaybackMix(Score score, Set<int> soundingParts) {
    final strips = playbackStrips(score);
    final solo = strips.any((s) => s.settings.solo);
    var channel = 0;
    for (final strip in strips) {
      final value = strip.settings;
      if (!value.isValid) throw const FormatException('Invalid mixer settings');
      if (value.mute ||
          (solo && !value.solo) ||
          value.volume == 0 ||
          !strip.parts.any(soundingParts.contains)) {
        continue;
      }
      if (channel == 9) {
        channel++;
      }
      if (channel > 15) {
        throw const FormatException(
          'Playback supports up to 15 sounding instruments. Mute some instruments and try again.',
        );
      }
      settings[channel] = value;
      for (final part in strip.parts) {
        channels[part] = channel;
      }
      channel++;
    }
  }
  final channels = <int, int>{};
  final settings = <int, PartPlayback>{};
}
