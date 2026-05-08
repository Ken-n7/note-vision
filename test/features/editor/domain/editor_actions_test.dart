import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

void main() {
  group('EditorEditIntent', () {
    test('symbol-selection intents accept replace and insert operations', () {
      final state = _selectedState(
        const Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
      );

      final replaced = state.moveSelectedSymbolUp();
      final inserted = state.insertRestAfterSelection();

      expect(replaced.selectedSymbol, isA<Note>());
      expect(inserted.selectedSymbol, isA<Rest>());
    });

    test('measure-context intents preserve measure selection without symbol selection', () {
      final score = Score(
        id: 'intent-measure',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(number: 1, symbols: []),
              Measure(number: 2, symbols: []),
            ],
          ),
        ],
      );

      final state = EditorState(
        score: score,
      ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);

      final changed = state.addMeasureAfterSelected();

      expect(changed.selectedPartIndex, 0);
      expect(changed.selectedMeasureIndex, 1);
      expect(changed.selectedSymbolIndex, isNull);
      expect(changed.selectedSymbol, isNull);
    });
  });

  group('EditorActions', () {
    test(
      'move up/down is diatonic with octave transitions and preserves alter',
      () {
        final upState = _selectedState(
          const Note(
            step: 'B',
            octave: 4,
            alter: -1,
            duration: 1,
            type: 'quarter',
          ),
        );

        final movedUp = upState.moveSelectedSymbolUp();
        final movedUpNote = movedUp.selectedSymbol! as Note;
        expect(movedUpNote.step, 'C');
        expect(movedUpNote.octave, 5);
        expect(movedUpNote.alter, -1);

        final downState = _selectedState(
          const Note(
            step: 'C',
            octave: 4,
            alter: 1,
            duration: 1,
            type: 'quarter',
          ),
        );

        final movedDown = downState.moveSelectedSymbolDown();
        final movedDownNote = movedDown.selectedSymbol! as Note;
        expect(movedDownNote.step, 'B');
        expect(movedDownNote.octave, 3);
        expect(movedDownNote.alter, 1);
      },
    );

    test('move up/down no-ops when selected symbol is rest', () {
      final state = _selectedState(const Rest(duration: 1, type: 'quarter'));

      expect(identical(state.moveSelectedSymbolUp(), state), isTrue);
      expect(identical(state.moveSelectedSymbolDown(), state), isTrue);
    });

    test('selectSymbolAt selects valid symbols and preserves measure context when cleared', () {
      final score = _twoMeasureScore();
      final selected = EditorState(score: score).selectSymbolAt(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 0,
      );

      expect(selected.selectedPartIndex, 0);
      expect(selected.selectedMeasureIndex, 0);
      expect(selected.selectedSymbolIndex, 0);
      expect(selected.selectedSymbol, same(score.parts[0].measures[0].symbols[0]));

      final cleared = selected.clearSymbolSelectionPreservingMeasureContext();
      expect(cleared.selectedPartIndex, 0);
      expect(cleared.selectedMeasureIndex, 0);
      expect(cleared.selectedSymbolIndex, isNull);
      expect(cleared.selectedSymbol, isNull);
    });

    test('deleteSymbolAtSelectionTarget removes editable symbols from a location', () {
      final score = _twoMeasureScore();
      final state = EditorState(score: score);

      final next = state.deleteSymbolAtSelectionTarget(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 0,
      );

      final symbols = next.score.parts[0].measures[0].symbols;
      expect(symbols.length, 1);
      expect(symbols.single, isA<Rest>());
      expect(next.selectedPartIndex, 0);
      expect(next.selectedMeasureIndex, 0);
    });

    test('duration change to same value is a no-op and does not push undo', () {
      final state = _selectedState(
        const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      );

      final next = state.setSelectedDuration(quarterDuration);

      expect(identical(next, state), isTrue);
      expect(next.undoStack, isEmpty);
    });

    test(
      'insert note/rest insert after selected symbol and auto-select',
      () {
        final score = Score(
          id: 's1',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                    Rest(duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );

        final state = EditorState(score: score).copyWith(
          selectedPartIndex: 0,
          selectedMeasureIndex: 0,
          selectedSymbolIndex: 0,
          selectedSymbol: score.parts[0].measures[0].symbols[0],
        );

        final withInsertedNote = state.insertNoteAfterSelection();
        final noteSymbols = withInsertedNote.score.parts[0].measures[0].symbols;
        expect(noteSymbols[1], isA<Note>());
        expect((noteSymbols[1] as Note).pitch, 'C4');
        expect(withInsertedNote.selectedSymbolIndex, 1);

        final withInsertedRest = withInsertedNote.insertRestAfterSelection();
        final restSymbols = withInsertedRest.score.parts[0].measures[0].symbols;
        expect(restSymbols[2], isA<Rest>());
        expect((restSymbols[2] as Rest).type, 'quarter');
        expect(withInsertedRest.selectedSymbolIndex, 2);
      },
    );

    test(
      'insert note/rest append to measure end when only measure context exists',
      () {
        final score = Score(
          id: 's1-measure-context',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                    Rest(duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );

        final state = EditorState(
          score: score,
        ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);

        final withInsertedNote = state.insertNoteAfterSelection();
        final noteSymbols = withInsertedNote.score.parts[0].measures[0].symbols;
        expect(noteSymbols.last, isA<Note>());
        expect((noteSymbols.last as Note).pitch, 'C4');
        expect(withInsertedNote.selectedSymbolIndex, noteSymbols.length - 1);
      },
    );

    test('non-editable symbol selection does not enable note-rest edit actions', () {
      final score = Score(
        id: 'metadata-selection',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Clef(sign: 'G', line: 2),
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      expect(identical(state.deleteSelectedSymbol(), state), isTrue);
      expect(identical(state.setSelectedDuration(quarterDuration), state), isTrue);

      final inserted = state.insertNoteAfterSelection();
      final symbols = inserted.score.parts[0].measures[0].symbols;

      expect(symbols.length, 3);
      expect(symbols[0], isA<Clef>());
      expect(symbols.last, isA<Note>());
      expect(inserted.selectedSymbolIndex, 2);
    });

    test('insert note/rest no-op with no measure context', () {
      final score = _baseScore(const []);
      final state = EditorState(score: score);

      expect(identical(state.insertNoteAfterSelection(), state), isTrue);
      expect(identical(state.insertRestAfterSelection(), state), isTrue);
    });

    test('insert after selection no-ops when measure is already full', () {
      final score = Score(
        id: 's-rhythm-insert-guard',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                timeSignature: TimeSignature(beats: 4, beatType: 4),
                symbols: [
                  Note(step: 'C', octave: 4, duration: 8, type: 'whole'),
                ],
              ),
            ],
          ),
        ],
      );

      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final next = state.insertRestAfterSelection();

      expect(identical(next, state), isTrue);
      expect(next.score.parts[0].measures[0].symbols, hasLength(1));
    });

    test('duration change no-ops when it would overflow the active measure', () {
      final score = Score(
        id: 's-rhythm-duration-guard',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                timeSignature: TimeSignature(beats: 4, beatType: 4),
                symbols: [
                  Note(step: 'C', octave: 4, duration: 4, type: 'half'),
                  Note(step: 'E', octave: 4, duration: 4, type: 'half'),
                ],
              ),
            ],
          ),
        ],
      );

      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 1,
        selectedSymbol: score.parts[0].measures[0].symbols[1],
      );

      final next = state.setSelectedDuration(wholeDuration);

      expect(identical(next, state), isTrue);
      expect(
        (next.score.parts[0].measures[0].symbols[1] as Note).duration,
        4,
      );
    });

    test('insertSymbolAtMeasureIndex no-ops for invalid part targets', () {
      final score = _baseScore(const []);
      final state = EditorState(score: score);

      final next = state.insertSymbolAtMeasureIndex(
        partIndex: 9,
        measureIndex: 0,
        insertIndex: 0,
        symbol: const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      );

      expect(identical(next, state), isTrue);
    });

    test(
      'setSelectedMeasureClef updates only the selected part and is undoable',
      () {
        final score = Score(
          id: 's-clef',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'Upper',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
            Part(
              id: 'p2',
              name: 'Lower',
              measures: [
                Measure(
                  number: 1,
                  clef: Clef(sign: 'F', line: 4),
                  symbols: [Rest(duration: 1, type: 'quarter')],
                ),
              ],
            ),
          ],
        );

        final state = EditorState(
          score: score,
        ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);

        final changed = state.setSelectedMeasureClef(
          const Clef(sign: 'C', line: 3),
        );

        expect(
          changed.score.parts[0].measures[0].clef,
          const Clef(sign: 'C', line: 3),
        );
        expect(
          changed.score.parts[1].measures[0].clef,
          const Clef(sign: 'F', line: 4),
        );
        expect(changed.selectedPartIndex, 0);
        expect(changed.selectedMeasureIndex, 0);
        expect(changed.undoStack, isNotEmpty);

        final undone = changed.undo();
        expect(undone.score.parts[0].measures[0].clef, isNull);
      },
    );

    test(
      'setSelectedMeasureClef can clear an explicit clef and no-ops when unchanged',
      () {
        final score = Score(
          id: 's-clear-clef',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'Upper',
              measures: [
                Measure(
                  number: 1,
                  clef: Clef(sign: 'G', line: 2),
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );

        final state = EditorState(
          score: score,
        ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);

        expect(
          identical(
            state.setSelectedMeasureClef(const Clef(sign: 'G', line: 2)),
            state,
          ),
          isTrue,
        );

        final cleared = state.setSelectedMeasureClef(null);
        expect(cleared.score.parts[0].measures[0].clef, isNull);
        expect(cleared.undoStack, isNotEmpty);
      },
    );

    test('moveSelectedSymbolToMeasureOffset keeps moved symbol selected', () {
      final score = Score(
        id: 's-move-measure',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
              Measure(number: 2, symbols: [Rest(duration: 2, type: 'half')]),
            ],
          ),
        ],
      );

      final selected = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final moved = selected.moveSelectedSymbolToMeasureOffset(1);

      expect(moved.selectedPartIndex, 0);
      expect(moved.selectedMeasureIndex, 1);
      expect(moved.selectedSymbolIndex, 1);
      expect(moved.selectedSymbol, isA<Note>());
      expect((moved.selectedSymbol! as Note).pitch, 'C4');
      expect(moved.score.parts[0].measures[1].symbols, hasLength(2));
      expect(moved.undoStack, isNotEmpty);
    });

    test('moveSelectedSymbolToMeasureOffset no-ops when destination measure is full', () {
      final score = Score(
        id: 's-rhythm-move-guard',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                timeSignature: TimeSignature(beats: 4, beatType: 4),
                symbols: [
                  Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                ],
              ),
              Measure(
                number: 2,
                symbols: [
                  Note(step: 'D', octave: 4, duration: 8, type: 'whole'),
                ],
              ),
            ],
          ),
        ],
      );

      final selected = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final next = selected.moveSelectedSymbolToMeasureOffset(1);

      expect(identical(next, selected), isTrue);
      expect(next.score.parts[0].measures[0].symbols, hasLength(1));
      expect(next.score.parts[0].measures[1].symbols, hasLength(1));
    });

    test(
      'deleting last symbol keeps measure context so insert can recover',
      () {
        final score = _baseScore(const [
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
        ]);
        final selectedState = EditorState(score: score).copyWith(
          selectedPartIndex: 0,
          selectedMeasureIndex: 0,
          selectedSymbolIndex: 0,
          selectedSymbol: score.parts[0].measures[0].symbols[0],
        );

        final cleared = selectedState.deleteSelectedSymbol();
        expect(cleared.selectedPartIndex, 0);
        expect(cleared.selectedMeasureIndex, 0);
        expect(cleared.selectedSymbolIndex, isNull);
        expect(cleared.selectedSymbol, isNull);

        final restored = cleared.insertNoteAfterSelection();
        expect(restored.score.parts[0].measures[0].symbols, hasLength(1));
        expect(restored.score.parts[0].measures[0].symbols.first, isA<Note>());
      },
    );

    test('reorderSymbolWithinMeasure reorders and preserves selection', () {
      final score = Score(
        id: 's-reorder',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      final selected = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final moved = selected.reorderSymbolWithinMeasure(
        measureIndex: 0,
        fromSymbolIndex: 0,
        toSymbolIndex: 2,
      );
      final symbols = moved.score.parts[0].measures[0].symbols;
      expect(symbols[0], isA<Rest>());
      expect((symbols[1] as Note).pitch, 'E4');
      expect((symbols[2] as Note).pitch, 'C4');
      expect(moved.selectedSymbolIndex, 2);
      expect((moved.selectedSymbol! as Note).pitch, 'C4');
      expect(moved.undoStack, isNotEmpty);
    });

    test(
      'moveSymbolToDest — same measure: reorders and preserves selection',
      () {
        final score = Score(
          id: 's1',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                    Rest(duration: 1, type: 'quarter'),
                    Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score).copyWith(
          selectedPartIndex: 0,
          selectedMeasureIndex: 0,
          selectedSymbolIndex: 0,
          selectedSymbol: score.parts[0].measures[0].symbols[0],
        );

        final next = state.moveSymbolToDest(
          fromPartIndex: 0,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0,
          toPartIndex: 0,
          toMeasureIndex: 0,
          toSymbolIndex: 2,
        );

        final symbols = next.score.parts[0].measures[0].symbols;
        expect(symbols[0], isA<Rest>());
        expect((symbols[1] as Note).step, 'E');
        expect((symbols[2] as Note).step, 'C');
        expect(next.selectedPartIndex, 0);
        expect(next.selectedMeasureIndex, 0);
        expect(next.selectedSymbolIndex, 2);
        expect((next.selectedSymbol! as Note).step, 'C');
        expect(next.undoStack, isNotEmpty);
      },
    );

    test('moveSymbolToDest — same measure same position: no-op', () {
      final score = Score(
        id: 's2',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );
      final state = EditorState(score: score);

      final next = state.moveSymbolToDest(
        fromPartIndex: 0,
        fromMeasureIndex: 0,
        fromSymbolIndex: 0,
        toPartIndex: 0,
        toMeasureIndex: 0,
        toSymbolIndex: 0,
      );

      expect(identical(next, state), isTrue);
      expect(next.undoStack, isEmpty);
    });

    test(
      'moveSymbolToDest — cross-measure: removes from source, inserts at destination',
      () {
        final score = Score(
          id: 's3',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                    Rest(duration: 1, type: 'quarter'),
                  ],
                ),
                Measure(
                  number: 2,
                  symbols: [
                    Note(step: 'G', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score);

        final next = state.moveSymbolToDest(
          fromPartIndex: 0,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0, // move C4 quarter
          toPartIndex: 0,
          toMeasureIndex: 1,
          toSymbolIndex: 0, // insert before G4
        );

        final m1 = next.score.parts[0].measures[0].symbols;
        final m2 = next.score.parts[0].measures[1].symbols;
        expect(m1, hasLength(1));
        expect(m1.single, isA<Rest>());
        expect(m2, hasLength(2));
        expect((m2[0] as Note).step, 'C');
        expect((m2[1] as Note).step, 'G');
        expect(next.selectedPartIndex, 0);
        expect(next.selectedMeasureIndex, 1);
        expect(next.selectedSymbolIndex, 0);
        expect((next.selectedSymbol! as Note).step, 'C');
        expect(next.undoStack, isNotEmpty);
      },
    );

    test(
      'moveSymbolToDest — cross-measure: destination index clamped to valid range',
      () {
        final score = Score(
          id: 's4',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
                Measure(
                  number: 2,
                  symbols: [
                    Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score);

        // toSymbolIndex=99 should clamp to 1 (after deleting C4 the dest has 1 symbol → valid insert range 0..1)
        final next = state.moveSymbolToDest(
          fromPartIndex: 0,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0,
          toPartIndex: 0,
          toMeasureIndex: 1,
          toSymbolIndex: 99,
        );

        final m2 = next.score.parts[0].measures[1].symbols;
        expect(m2, hasLength(2));
        expect((m2.last as Note).step, 'C');
      },
    );

    test('moveSymbolToDest — cross-part: moves symbol between parts', () {
      final score = Score(
        id: 's5',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'Treble',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 5, duration: 1, type: 'quarter'),
                  Note(step: 'D', octave: 5, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
          Part(
            id: 'p2',
            name: 'Bass',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 3, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );
      final state = EditorState(score: score);

      final next = state.moveSymbolToDest(
        fromPartIndex: 0,
        fromMeasureIndex: 0,
        fromSymbolIndex: 1, // D5 from treble
        toPartIndex: 1,
        toMeasureIndex: 0,
        toSymbolIndex: 0, // insert before C3 in bass
      );

      expect(next.score.parts[0].measures[0].symbols, hasLength(1));
      expect(
        (next.score.parts[0].measures[0].symbols.single as Note).step,
        'C',
      );
      expect(next.score.parts[1].measures[0].symbols, hasLength(2));
      expect((next.score.parts[1].measures[0].symbols[0] as Note).step, 'D');
      expect(next.selectedPartIndex, 1);
      expect(next.selectedMeasureIndex, 0);
      expect(next.selectedSymbolIndex, 0);
    });

    test(
      'moveSymbolToDest — guard: invalid fromPartIndex returns unchanged state',
      () {
        final score = Score(
          id: 's6',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score);

        final next = state.moveSymbolToDest(
          fromPartIndex: 5,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0,
          toPartIndex: 0,
          toMeasureIndex: 0,
          toSymbolIndex: 0,
        );

        expect(identical(next, state), isTrue);
      },
    );

    test(
      'moveSymbolToDest — guard: invalid toPartIndex returns unchanged state',
      () {
        final score = Score(
          id: 's7',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score);

        final next = state.moveSymbolToDest(
          fromPartIndex: 0,
          fromMeasureIndex: 0,
          fromSymbolIndex: 0,
          toPartIndex: 5,
          toMeasureIndex: 0,
          toSymbolIndex: 0,
        );

        expect(identical(next, state), isTrue);
      },
    );

    test(
      'reorderSymbolWithinMeasure cannot move symbol across measure boundary',
      () {
        final score = Score(
          id: 's-multi',
          title: 't',
          composer: 'c',
          parts: const [
            Part(
              id: 'p1',
              name: 'P1',
              measures: [
                Measure(
                  number: 1,
                  symbols: [
                    Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  ],
                ),
                Measure(
                  number: 2,
                  symbols: [Rest(duration: 1, type: 'quarter')],
                ),
              ],
            ),
          ],
        );
        final state = EditorState(score: score);

        final unchanged = state.reorderSymbolWithinMeasure(
          measureIndex: 0,
          fromSymbolIndex: 0,
          toSymbolIndex: 1,
        );

        expect(identical(unchanged, state), isTrue);
        expect(unchanged.undoStack, isEmpty);
        expect(
          unchanged.score.parts[0].measures[1].symbols.single,
          isA<Rest>(),
        );
      },
    );
  });
}

EditorState _selectedState(ScoreSymbol symbol) {
  final score = _baseScore([symbol]);
  return EditorState(score: score).copyWith(
    selectedPartIndex: 0,
    selectedMeasureIndex: 0,
    selectedSymbolIndex: 0,
    selectedSymbol: score.parts[0].measures[0].symbols[0],
  );
}

Score _baseScore(List<ScoreSymbol> symbols) => Score(
  id: 'score-1',
  title: 'Sample',
  composer: 'Composer',
  parts: [
    Part(
      id: 'part-1',
      name: 'Piano',
      measures: [Measure(number: 1, symbols: symbols)],
    ),
  ],
);

Score _twoMeasureScore() => const Score(
  id: 'score-2',
  title: 'Sample',
  composer: 'Composer',
  parts: [
    Part(
      id: 'part-1',
      name: 'Piano',
      measures: [
        Measure(
          number: 1,
          symbols: [
            Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
            Rest(duration: 1, type: 'quarter'),
          ],
        ),
        Measure(
          number: 2,
          symbols: [
            Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
          ],
        ),
      ],
    ),
  ],
);
