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

/// Each instrument gets its own MIDI channel, so its sound, volume and pan
/// apply to it alone; instruments with the same settings (a band's Clarinet
/// 1-3) share one, which lets a concert band fit the 15 pitched channels.
/// Note-offs are counted per channel and pitch, so a shared unison holds
/// until its last note ends. Channel 10 (index 9) is for percussion: drum
/// staves share it, its program choosing the kit.
class PlaybackMix {
  PlaybackMix(Score score, Set<int> soundingParts) {
    final strips = playbackStrips(score);
    final solo = strips.any((s) => s.settings.solo);
    var channel = 0;
    final shared = <PartPlayback, int>{};
    for (final strip in strips) {
      final value = strip.settings;
      if (!value.isValid) throw const FormatException('Invalid mixer settings');
      if (value.mute ||
          (solo && !value.solo) ||
          value.volume == 0 ||
          !strip.parts.any(soundingParts.contains)) {
        continue;
      }
      if (score.parts[strip.parts.first].isPercussion) {
        settings[9] = value;
        for (final part in strip.parts) {
          channels[part] = 9;
        }
        continue;
      }
      if (shared[value] case final same?) {
        for (final part in strip.parts) {
          channels[part] = same;
        }
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
      shared[value] = channel;
      for (final part in strip.parts) {
        channels[part] = channel;
      }
      channel++;
    }
  }
  final channels = <int, int>{};
  final settings = <int, PartPlayback>{};
}
