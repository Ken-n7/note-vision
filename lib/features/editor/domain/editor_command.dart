import '../../../core/models/note.dart';
import '../../../core/models/rest.dart';
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
  delete('Delete symbol', 'Edit', 'Remove the selected note or rest', 'Delete');

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
    if (!state.hasEditableSymbolSelection) return 'Select a note or rest';
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
    if (duration case final spec?) return state.setSelectedDuration(spec);
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
      delete => state.deleteSelectedSymbol(),
      _ => state,
    };
  }
}
