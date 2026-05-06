# Refactor Steps

This document tracks the staged maintainability and scalability refactor for the editor-heavy parts of Note Vision.

## Goals

- Reduce responsibility concentration in `EditorShellScreen`
- Preserve behavior while extracting smaller units
- Keep playback, editor actions, and persistence easier to test in isolation
- Run focused tests after each step so regressions are caught immediately

## Sequence

1. Extract editor feedback and save/export helpers out of `EditorShellScreen`.
   - Move banner/snackbar/save/export helper logic into smaller private collaborators or widgets.
   - Keep behavior identical.
   - Run:
     - `flutter test test/features/editor/presentation/editor_shell_screen_test.dart`

2. Extract page navigation and playback-follow logic from `EditorShellScreen`.
   - Isolate page-start/page-count/page-follow calculations into dedicated helpers.
   - Keep editor UI behavior unchanged.
   - Run:
     - `flutter test test/features/editor/presentation/editor_shell_screen_test.dart`
     - `flutter test test/features/editor/domain/editor_actions_test.dart`

3. Reduce `EditorShellScreen` widget responsibility by splitting major UI sections.
   - Separate header/actions, notation container, and inspector coordination into clearer units.
   - Avoid changing external behavior.
   - Run:
     - `flutter test test/features/editor/presentation/editor_shell_screen_test.dart`

4. Simplify score mutation paths in core models.
   - Reduce repeated manual measure reconstruction in `Score`.
   - Centralize replacement helpers so new fields are less expensive to add safely.
   - Run:
     - `flutter test test/features/editor/domain/editor_actions_test.dart`
     - `flutter test test/core/models/project_serialization_test.dart`
     - `flutter test test/core/models/score_edit_helpers_test.dart`

5. Improve editor state/edit seams.
   - Keep selection/history behavior intact while making state transitions easier to follow and extend.
   - Run:
     - `flutter test test/features/editor/model/editor_state_test.dart`
     - `flutter test test/features/editor/domain/editor_actions_test.dart`

6. Review service boundaries around playback and storage.
   - Introduce cleaner seams where feasible without changing app behavior.
   - Prefer incremental extraction over architectural churn.
   - Run:
     - `flutter test test/core/services/playback_converter_test.dart`
     - `flutter test test/features/editor/presentation/editor_shell_screen_test.dart`

7. Finish with a broader regression pass.
   - Run the focused suites touched during the refactor.
   - If stable, optionally expand to additional related feature suites.

## Working Rules

- Make one scoped refactor step at a time.
- Test after each step before continuing.
- Prefer behavior-preserving extraction first, structural cleanup second.
- Avoid running bulk formatting if it reintroduces local lint/style issues.
