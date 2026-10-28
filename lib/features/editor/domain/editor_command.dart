import '../../../core/models/note.dart';
import '../../../core/models/spanner.dart';
import '../../../core/models/rest.dart';
import '../../../core/services/transposer.dart';
import '../model/editor_state.dart';
import 'editor_actions.dart';

/// Commands share availability and undo behavior between search and keyboards.
enum EditorCommand {
  undo('Undo', 'History', 'Restore the previous edit', 'Ctrl/Cmd + Z'),
  redo('Redo', 'History', 'Restore an undone edit', 'Ctrl/Cmd + Shift + Z'),
  pitchUp('Raise pitch', 'Pitch', 'Move up one diatonic step', 'Up'),
  pitchDown('Lower pitch', 'Pitch', 'Move down one diatonic step', 'Down'),
  octaveUp('Raise octave', 'Pitch', 'Move up one octave', 'Ctrl/Cmd + Up'),
  octaveDown(
    'Lower octave',
    'Pitch',
    'Move down one octave',
    'Ctrl/Cmd + Down',
  ),
  whole('Whole duration', 'Rhythm', 'Set a whole note or rest', '7'),
  half('Half duration', 'Rhythm', 'Set a half note or rest', '6'),
  quarter('Quarter duration', 'Rhythm', 'Set a quarter note or rest', '5'),
  eighth('Eighth duration', 'Rhythm', 'Set an eighth note or rest', '4'),
  sixteenth('Sixteenth duration', 'Rhythm', 'Set a 16th note or rest', '3'),
  dot('Toggle augmentation dot', 'Rhythm', 'Add or remove a duration dot', '.'),
  sharp('Sharp accidental', 'Pitch', 'Write a sharp on the selected note'),
  flat('Flat accidental', 'Pitch', 'Write a flat on the selected note'),
  natural('Natural accidental', 'Pitch', 'Write an explicit natural'),
  clearAccidental('Remove accidental', 'Pitch', 'Use the active key signature'),
  noteToRest('Convert note to rest', 'Edit', 'Keep its duration and position'),
  restToNote(
    'Convert rest to note',
    'Edit',
    'Create a C4 note with the same duration',
  ),
  addThird(
    'Add third above',
    'Chords',
    'Add a chord note a third above the selected note',
    'Alt + 3',
  ),
  staccato('Staccato', 'Articulations', 'Play the note short', 'Shift + S'),
  staccatissimo(
    'Staccatissimo',
    'Articulations',
    'Play the note very short',
  ),
  tenuto('Tenuto', 'Articulations', 'Hold the note full length', 'Shift + N'),
  accent('Accent', 'Articulations', 'Stress the note', 'Shift + V'),
  marcato('Marcato', 'Articulations', 'Stress the note strongly', 'Shift + O'),
  fermata('Fermata', 'Articulations', 'Hold the note or rest longer'),
  trill('Trill', 'Ornaments', 'Alternate with the note above'),
  mordent('Mordent', 'Ornaments', 'The note, the note below, the note'),
  turn('Turn', 'Ornaments', 'Above, the note, below, the note'),
  crescendo('Crescendo', 'Dynamics', 'A hairpin growing louder', '<'),
  diminuendo('Diminuendo', 'Dynamics', 'A hairpin growing softer', '>'),
  triplet(
    'Triplet',
    'Rhythm',
    'Fill the selected note or rest\'s time with three shorter notes',
    'Ctrl/Cmd + 3',
  ),
  tie(
    'Tie',
    'Notation',
    'Tie the selected note to the next note of the same pitch',
    '+',
  ),
  slur(
    'Slur',
    'Notation',
    'Slur the selected notes, or the selected note to the next',
    'S',
  ),
  selectAll(
    'Select all',
    'Selection',
    'Select every note and rest in this staff',
    'Ctrl/Cmd + A',
  ),
  selectBar('Select bar', 'Selection', 'Select every note and rest in the bar'),
  delete(
    'Delete selection',
    'Edit',
    'Remove the selected notes and rests',
    'Delete',
  );

  const EditorCommand(
    this.label,
    this.group,
    this.description, [
    this.shortcut,
  ]);

  final String label, group, description;
  final String? shortcut;

  DurationSpec? get duration => switch (this) {
    whole => wholeDuration,
    half => halfDuration,
    quarter => quarterDuration,
    eighth => eighthDuration,
    sixteenth => sixteenthDuration,
    _ => null,
  };

  SpannerKind? get hairpin => switch (this) {
    crescendo => SpannerKind.crescendo,
    diminuendo => SpannerKind.diminuendo,
    _ => null,
  };

  /// The articulation or ornament this command toggles.
  Articulation? get mark => switch (this) {
    staccato => Articulation.staccato,
    staccatissimo => Articulation.staccatissimo,
    tenuto => Articulation.tenuto,
    accent => Articulation.accent,
    marcato => Articulation.marcato,
    fermata => Articulation.fermata,
    trill => Articulation.trill,
    mordent => Articulation.mordent,
    turn => Articulation.turn,
    _ => null,
  };

  int? get pitchSteps => switch (this) {
    pitchUp => 1,
    pitchDown => -1,
    octaveUp => 7,
    octaveDown => -7,
    _ => null,
  };

  /// A reason is also the disabled state, so search never offers silent no-ops.
  String? unavailableReason(EditorState state) {
    if (this == undo) return state.canUndo ? null : 'No edits to undo';
    if (this == redo) return state.canRedo ? null : 'No edits to redo';
    if (this == selectAll) {
      return state.musicSymbolCount == 0 ? 'Add notes first' : null;
    }
    if (this == selectBar) {
      return identical(state.selectBar(), state)
          ? 'Select a bar with notes or rests'
          : null;
    }
    if (mark case final mark?) return state.markUnavailableReason(mark);
    if (hairpin case final kind?) return state.hairpinUnavailableReason(kind);
    if (this == triplet) return state.tupletUnavailableReason(3);
    if (this == tie) return state.tieUnavailableReason;
    if (this == slur) return state.slurUnavailableReason;
    if (!state.hasEditableSymbolSelection) return 'Select a note or rest';
    if (state.hasRange) {
      // Pitch moves apply to the whole range, as in MuseScore Studio.
      return this == delete || pitchSteps != null
          ? null
          : 'Select a single note or rest';
    }
    if (this == restToNote) {
      return state.selectedSymbol is Rest ? null : 'Select a rest';
    }
    if (this == delete) return null;
    if (duration case final spec?) {
      return state.canSetSelectedDuration(spec)
          ? null
          : 'Not enough room in this bar';
    }
    if (this == dot) {
      return state.canToggleSelectedDot ? null : 'Not enough room in this bar';
    }
    if (state.selectedSymbol is! Note) return 'Select a note';
    if (pitchSteps case final steps?) {
      return state.canMoveSelectedPitch(steps)
          ? null
          : 'Outside the supported pitch range';
    }
    if (this == noteToRest && !state.canConvertSelectedNoteToRest) {
      return 'Select a note outside a chord';
    }
    return null;
  }

  EditorState execute(EditorState state) {
    if (unavailableReason(state) != null) return state;
    if (mark case final mark?) return state.toggleMark(mark);
    if (hairpin case final kind?) return state.toggleHairpin(kind);
    if (duration case final spec?) return state.setSelectedDuration(spec);
    if (pitchSteps case final steps? when state.hasRange) {
      return state.transposeSelection(
        TransposeOptions(
          mode: steps.abs() == 7
              ? TransposeMode.byInterval
              : TransposeMode.diatonic,
          interval: steps.abs() == 7 ? 25 : 1,
          direction: steps > 0
              ? TransposeDirection.up
              : TransposeDirection.down,
        ),
      );
    }
    if (pitchSteps case final steps?) return state.moveSelectedPitch(steps);
    return switch (this) {
      undo => state.applyUndo(),
      redo => state.applyRedo(),
      dot => state.toggleSelectedDot(),
      sharp => state.setSelectedNoteAccidental(1),
      flat => state.setSelectedNoteAccidental(-1),
      natural => state.setSelectedNoteAccidental(0),
      clearAccidental => state.setSelectedNoteAccidental(null),
      noteToRest => state.convertSelectedNoteToRest(),
      restToNote => state.convertSelectedRestToNote(),
      addThird => state.addChordInterval(3),
      triplet => state.makeTuplet(3),
      tie => state.toggleTie(),
      slur => state.toggleSlur(),
      selectAll => state.selectAllInPart(),
      selectBar => state.selectBar(),
      delete => state.deleteSelection(),
      _ => state,
    };
  }
}
