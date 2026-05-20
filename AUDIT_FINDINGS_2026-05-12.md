# Note Vision Deep-Dive Audit Findings

Generated: 2026-05-12, workspace local time

Scope: Flutter/Dart app under `/home/ken/Workspace/Note-Vision/app`.

Audit approach:
- Spawned separate read-only specialist agents for detection/mapping, UI/UX, architecture/storage, and test/build/performance.
- Ran local code inspection across core services, scan flow, mapping, editor actions, platform config, tests, and workflows.
- Ran `flutter analyze`, `flutter test --no-pub`, and `flutter pub outdated`.

Verification summary:
- `flutter analyze`: passed, no issues found.
- `flutter test --no-pub`: passed, all tests passed.
- `flutter pub outdated`: several dependencies are behind; direct packages constrained below latest include `file_picker`, `share_plus`, and `xml`.

## Executive Summary

The current test suite is healthy, but the highest-risk problems sit at system boundaries that tests mostly do not cover:

- The real TFLite detector contract appears mismatched with the parser. If true, real scans can fail or produce garbage detections even though mock mapping tests pass.
- Production detections never populate `DetectedBarline`, so accurate measure grouping and repeat reconstruction are mostly test-only behavior today.
- Several user-data paths can lose or hide scores: non-atomic project writes, corrupt index/project handling, timestamp ID collisions, and mutable model lists.
- The UI uses many custom `GestureDetector` controls, plus several fixed/dense layouts that are fragile for accessibility, keyboard use, landscape, and larger text.
- Platform release readiness has gaps: iOS privacy strings, macOS file entitlements, Android release signing fallback, and CI version drift.

Recommended first fix order:
1. Fix and test the TFLite output contract against the bundled model.
2. Add real barline detection and broaden staff-neighborhood filtering for ledger notes.
3. Harden project persistence with atomic writes, corruption recovery, and collision-resistant IDs.
4. Add iOS privacy strings and dispose the native TFLite interpreter.
5. Replace custom tap wrappers.

## Critical Findings

### 1. TFLite Output Is Parsed As The Wrong Format

Severity: Critical

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:181` allocates a fixed output shaped as `[1, 300, 6]`.
- `lib/features/detection/data/tflite_symbol_detector.dart:250` parses each row as `[x1, y1, x2, y2, confidence, classId]`.
- A specialist model-contract audit found the bundled `assets/models/best_int8.tflite` metadata reports `nms: false` with 57 class names. Non-NMS YOLO TFLite exports normally return raw boxes and class-score channels, not post-NMS rows.
- Existing detector tests only cover confidence threshold helpers in `test/features/detection/data/tflite_symbol_detector_test.dart`, not the bundled model output shape.

Impact:
- Real scans may throw on tensor shape mismatch or silently interpret raw box/logit channels as final detections.
- Downstream mapping and editor flows can look functional in tests while production scan results are invalid.

Suggested fix:
- Allocate output buffers from `getOutputTensor(0).shape`, not a hard-coded `[1, 300, 6]`.
- Decode the actual YOLO raw output format: candidate boxes, class scores, best-class selection, confidence thresholding, coordinate conversion, and class-aware NMS.
- Alternatively re-export the model with NMS and lock the parser to that exact tensor contract.
- Add a test that loads the bundled model and asserts output shape/metadata against the parser contract.

## High Findings

### 2. Real Scans Never Produce `DetectedBarline`s

Severity: High

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:109` returns `DetectionResult(symbols: symbols, staffs: mergedStaves)` with no `barlines`.
- `lib/features/detection/domain/music_symbol.dart` has no barline class in the enum.
- `lib/features/mapping/domain/internal/measure_grouper.dart:35` depends on `detection.barlines` for barline-based measure grouping.
- Mapping tests inject mock `DetectedBarline`s directly, e.g. `test/features/mapping/domain/detection_to_score_mapper_service_test.dart:41`.

Impact:
- Production scan mapping falls back to beat-count splitting instead of true visual measure boundaries.
- Repeat barline reconstruction is mostly limited to mock/test inputs.

Suggested fix:
- Add a barline detection stage, likely vertical projection constrained to each detected staff.
- Or train/export a model class for barlines.
- Populate `DetectionResult.barlines` with `staffId` and add scan-to-mapping integration tests using real detector-shaped output.

### 3. Out-Of-Staff Filtering Can Drop Ledger Notes Before Mapping

Severity: High

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:100` filters musical detections through `_filterOutsideStaves`.
- `lib/features/detection/data/tflite_symbol_detector.dart:226` keeps a symbol only if its bbox center is between `staff.topY` and `staff.bottomY`.
- The mapper later has ledger-line support, but `legerLine` and out-of-staff noteheads may be removed before the mapper sees them.

Impact:
- Notes above or below the staff can disappear from reconstructed scores.
- Ledger-line pitch logic becomes less useful in real scans.

Suggested fix:
- Expand the vertical staff neighborhood by several staff spaces.
- Always preserve noteheads, `legerLine`, accidentals, clefs, rests, repeat dots, and nearby signature symbols within a reasonable distance of the nearest staff.

### 4. iOS Camera And Photo Privacy Strings Are Missing

Severity: High

Evidence:
- `ios/Runner/Info.plist` has no `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, or `NSPhotoLibraryAddUsageDescription`.
- The app uses image picking and camera/gallery paths in `lib/features/capture/presentation/capture_screen.dart`, `lib/features/landing/presentation/onboarding_screen.dart`, `lib/features/profile/presentation/edit_profile_sheet.dart`, and `lib/core/utils/image_picker_helper.dart`.

Impact:
- iOS camera/photo flows can crash at runtime or fail App Review privacy checks.

Suggested fix:
- Add explicit iOS privacy strings describing score capture, image import, and profile photo selection.

### 5. Project Saves Are Non-Atomic And Can Lose User Scores

Severity: High

Evidence:
- `lib/core/services/project_storage_service.dart:48` writes directly to `{id}.json`.
- `lib/core/services/project_storage_service.dart:49` updates the SharedPreferences index as a separate step.

Impact:
- A crash during write can truncate an existing project file.
- A crash after file write but before index update can leave a saved project invisible to `loadAllProjects`.

Suggested fix:
- Write to a temporary file, flush, then atomically rename.
- Update the index after the file is safely in place.
- Add index rebuild logic that scans `{docs}/projects/*.json` when the index and filesystem disagree.

### 6. One Corrupt Index Or Project File Can Hide The Collection

Severity: High

Evidence:
- `lib/core/services/project_storage_service.dart:58` directly decodes project JSON.
- `lib/core/services/project_storage_service.dart:92` directly decodes the SharedPreferences project index.
- `lib/core/services/project_storage_service.dart:64` loops through index entries without per-project error isolation.
- `CollectionScreen` catches load failure and can leave the collection empty.

Impact:
- One bad file or bad index entry can prevent the user from seeing otherwise valid projects.

Suggested fix:
- Catch `FormatException` and schema errors per project.
- Quarantine or skip corrupt files, rebuild a clean index, and surface a recovery message.
- Add tests for malformed index JSON and malformed project JSON.

### 7. Custom Tap Targets Lose Accessibility And Platform Behavior

Severity: High

Evidence:
- `lib/core/widgets/tappable_button.dart:18` wraps controls in `GestureDetector`.
- Drawer and collection controls also use `GestureDetector`, e.g. `lib/core/widgets/drawer.dart:246` and `lib/features/collection/presentation/collection_screen.dart:416`.

Impact:
- Many controls miss Material focus, keyboard activation, hover, ripple, and semantics.
- This hurts accessibility and desktop/web usability.

Suggested fix:
- Prefer `InkWell`, `IconButton`, `TextButton`, `FilledButton`, or `Semantics`-wrapped controls.
- Add widget tests for keyboard activation and semantic labels on primary controls.

## Medium Findings

### 8. Model Key-Signature Labels Are Ignored

Severity: Medium

Evidence:
- `lib/features/detection/domain/music_symbol.dart:24` includes `keyFlat`, `keyNatural`, and `keySharp`.
- `lib/features/mapping/domain/internal/symbol_classifier.dart:33` recognizes only `accidentalFlat`, `accidentalSharp`, and `accidentalNatural` as key-signature accidentals.
- `lib/features/mapping/domain/internal/signature_inferrer.dart:83` infers key signatures from those recognized accidental types.

Impact:
- Real model detections labeled `keySharp` or `keyFlat` become unsupported symbols and key signatures are lost.

Suggested fix:
- Treat `keySharp`, `keyFlat`, and `keyNatural` as signature symbols.
- Keep key-signature labels separate from note-level accidentals so they are not matched to notes.

### 9. 16th/32nd/64th/128th Flags Are Detected But Not Mapped

Severity: Medium

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:27` to `:34` has thresholds for deeper flags.
- `lib/features/mapping/domain/internal/symbol_classifier.dart:18` supports only `flag8thUp` and `flag8thDown`.
- `lib/features/mapping/domain/internal/semantic_inferrer.dart:289` maps flagged black noteheads only to eighth notes.

Impact:
- A 16th or shorter flagged note can be downgraded to quarter/eighth or ignored with a warning.

Suggested fix:
- Classify all flag depths.
- Carry note duration through `StemLink` or a richer association result.
- Add mapping tests for 16th, 32nd, 64th, and 128th flags.

### 10. `combTimeSignature` Is Classified But Cannot Be Interpreted

Severity: Medium

Evidence:
- `lib/features/mapping/domain/internal/symbol_classifier.dart:31` treats `combTimeSignature` as a time-signature symbol.
- `lib/features/mapping/domain/internal/signature_inferrer.dart:44` only handles common/cut symbols or digit labels.

Impact:
- A detection that only contains `combTimeSignature` is collected as a signature symbol but then dropped with a warning.

Suggested fix:
- Remove it from supported time signatures until it can be decoded.
- Or infer digits from associated detections/metadata if the model provides that information.

### 11. TFLite Interpreter Is Not Disposed By The Scan Flow

Severity: Medium

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:56` has a `dispose()` method.
- `lib/features/scan/presentation/scan_screen.dart:381` creates `TfliteSymbolDetector()` inline.
- `ScanViewModel` does not override `dispose()` to close it.

Impact:
- Repeated scans can leak native interpreter resources.

Suggested fix:
- Add a disposable contract to `SymbolDetector`, or have `ScanViewModel` own a `TfliteSymbolDetector` and close it in `dispose()`.
- Add a widget/unit test with a fake disposable detector.

### 12. Staff Detection Runs Synchronously On The UI Isolate

Severity: Medium

Evidence:
- `lib/features/preprocessing/data/basic_image_preprocessor.dart:9` uses `compute`.
- `lib/features/scan/presentation/scan_viewmodel.dart:43` runs `_staffDetector.detect(preprocessed.bytes)` synchronously.
- `lib/features/preprocessing/data/horizontal_projection_staff_detector.dart:50` decodes and scans every pixel with nested loops.

Impact:
- Large images can freeze the UI during staff detection.

Suggested fix:
- Run staff detection in an isolate.
- Or combine staff detection into preprocessing while the image is already decoded.

### 13. TFLite Input Preparation Allocates Too Much Per Scan

Severity: Medium

Evidence:
- `lib/features/detection/data/tflite_symbol_detector.dart:196` builds a `Float32List`.
- `lib/features/detection/data/tflite_symbol_detector.dart:164` copies that into deeply nested Dart lists.

Impact:
- Every inference creates significant boxed/list overhead for a 640x640x3 tensor.

Suggested fix:
- Pass a reshaped typed buffer directly if supported by `tflite_flutter`.
- Reuse preallocated input and output buffers.

### 14. Timestamp IDs Can Collide And Overwrite Projects

Severity: Medium

Evidence:
- `lib/core/models/project.dart:24` derives project IDs from `DateTime.now().millisecondsSinceEpoch`.
- `lib/features/collection/presentation/collection_screen.dart:210` also uses millisecond IDs for blank scores.
- Storage maps IDs directly to `{id}.json`.

Impact:
- Two projects created in the same millisecond can collide and overwrite.

Suggested fix:
- Use UUID, ULID, or another collision-resistant ID.
- Detect existing files before saving.

### 15. Model Lists Are Mutable Despite Final Fields

Severity: Medium

Evidence:
- `Score.parts`, `Part.measures`, and `Measure.symbols` are final list fields but not consistently wrapped as unmodifiable in constructors.
- Undo snapshots store direct `Score` references.

Impact:
- Accidental external mutation can corrupt undo/redo history, editor state, or persisted data.

Suggested fix:
- Wrap lists with `List.unmodifiable` in model constructors/factories.
- Consider generated immutable models or explicit copy constructors.

### 16. Profile Photo Storage Leaves Stale Private Files

Severity: Medium

Evidence:
- `lib/features/landing/presentation/onboarding_screen.dart:110` writes to `profile_photo$ext`.
- `lib/features/profile/presentation/edit_profile_sheet.dart:106` writes to `profile_photo$ext`.
- Removing a photo clears the profile path but does not delete the old file.

Impact:
- Old profile images can remain on disk after replacement/removal.

Suggested fix:
- Store profile photos in a dedicated directory.
- Delete the previous file on replace/remove.
- Use a stable filename or cleanup old extensions.

### 17. Metadata Edits Bypass Undo And Save Asynchronously Without Feedback

Severity: Medium

Evidence:
- `lib/features/editor/presentation/editor_shell_screen.dart:522` updates title/composer through `copyWith`.
- `lib/features/editor/presentation/editor_shell_screen.dart:532` calls `_onSave()` without awaiting.
- The edit does not flow through `applyEdit`, so undo/redo cannot restore metadata.

Impact:
- Metadata changes behave differently from notation edits.
- Save failures may not be tied clearly to the metadata action.

Suggested fix:
- Route metadata edits through the same history mechanism as score edits.
- Await `_onSave()` or explicitly use `unawaited` and show clear save state.

### 18. No-Detection Feedback Is Too Easy To Miss

Severity: Medium

Evidence:
- `lib/features/scan/presentation/scan_screen.dart:132` shows a snackbar for no detections.
- `lib/features/scan/presentation/widgets/scan_actions.dart:134` silently disables Continue.

Impact:
- Users may not understand why they cannot continue after the snackbar disappears.

Suggested fix:
- Add a persistent inline empty/error panel near the scan preview.
- Include concrete next actions: retake, improve lighting, crop page, import file.

### 19. Collection Controls Hide Important Actions

Severity: Medium

Evidence:
- Project deletion is hidden behind long-press.

Impact:
- Users may not discover deletion.

Suggested fix:
- Add visible project overflow actions for rename/delete/export.

### 20. Profile And Edit-Profile Layouts Are Fragile

Severity: Medium

Evidence:
- Profile card uses a fixed row with avatar, text, spacing, and edit button.
- Stats are always a 2-column grid with three cards.
- Edit profile bottom sheet is a non-scrollable column with keyboard inset padding.
- Error text and character counter share one row without flexible wrapping.

Impact:
- Narrow screens, landscape, keyboard, or larger text can overflow or create awkward empty space.

Suggested fix:
- Use responsive wrapping or breakpoints for profile header and stats.
- Make bottom sheet content scrollable and let validation text wrap.

### 21. Drawer Is Fixed Width And Non-Scrollable

Severity: Medium

Evidence:
- Drawer uses a fixed 260px width and non-scrollable layout.
- Header plus sections can overflow on short landscape devices or large text.

Impact:
- Navigation can become inaccessible on small heights or accessibility text sizes.

Suggested fix:
- Use a scrollable drawer body with responsive width constraints.

### 22. Inspector Screens Need Layout And Visual-System Cleanup

Severity: Medium

Evidence:
- Detection inspector uses a blue dev palette while MusicXML inspector uses the main gold/black theme.
- Raw JSON/XML/debug panels are not horizontally scrollable.

Impact:
- Dev tools feel inconsistent and long debug lines can become unreadable.

Suggested fix:
- Either mark both as dev tools with a distinct visual system or align both to the app theme.
- Add horizontal scrolling and copy actions for raw text panels.

### 23. Editor Header And Playback Controls Are Dense Fixed Rows

Severity: Medium

Evidence:
- Editor header, save/menu, undo/redo, scrubber, and tempo controls share tight fixed-height rows.
- Some controls are shrink-wrapped below comfortable mobile target sizes.

Impact:
- Narrow phones and larger text can crowd or clip important controls.

Suggested fix:
- Use responsive command grouping, overflow menus, and minimum tap target constraints.
- Add tests for text scaling and narrow viewport layouts.

### 24. Horizontal Staff Projection Assumes Staff Lines Cover 25 Percent Of Image Width

Severity: Medium

Evidence:
- `lib/features/preprocessing/data/horizontal_projection_staff_detector.dart:56` requires candidate rows to have dark pixels across `0.25 * imageWidth`.
- Tests use full-width synthetic staff lines.

Impact:
- Photos with large margins, partial systems, skew, or cropped staff fragments can fail staff detection.

Suggested fix:
- Compute projection over detected content bounds.
- Consider adaptive thresholds or connected components before grouping lines.
- Add tests for large margins and partial-width staff lines.

### 25. Invalid Or Unsupported Images Can Crash Decode Paths

Severity: Medium

Evidence:
- `lib/features/preprocessing/data/basic_image_preprocessor.dart:16` uses `img.decodeImage(bytes)!`.
- `lib/features/detection/data/tflite_symbol_detector.dart:67` uses `img.decodeImage(input.bytes)!`.

Impact:
- Bad image bytes can throw a null-check crash instead of showing a controlled error message.

Suggested fix:
- Handle null decode results and throw domain-specific scan/import exceptions with user-friendly messages.

## Low Findings And Improvements

### 26. Android Release Builds Can Fall Back To Debug Signing

Severity: Low/Medium

Evidence:
- `android/app/build.gradle.kts` uses release signing only if `key.properties` exists, otherwise `signingConfigs.getByName("debug")`.

Impact:
- A release-looking APK can be produced with debug signing outside CI.

Suggested fix:
- Fail release builds when release signing is missing, or require an explicit local override for debug signing.

### 27. macOS Sandbox Lacks User-Selected File Read/Write Entitlement

Severity: Low/Medium

Evidence:
- `macos/Runner/Release.entitlements` only enables app sandbox.
- The app uses file picker save flows for PDF and MusicXML export.

Impact:
- macOS export/import workflows can fail under sandboxed release builds.

Suggested fix:
- Add `com.apple.security.files.user-selected.read-write` where needed.

### 28. CI And Release Flutter Versions Drift

Severity: Low

Evidence:
- `.github/workflows/ci.yml` uses floating `stable`.
- `.github/workflows/build-release.yml` pins Flutter `3.38.7`.
- CI runs analyze/test but not a platform build smoke test.

Impact:
- CI and release can validate different SDKs.
- Platform build breakage can be missed until release.

Suggested fix:
- Pin CI to the same Flutter version as release.
- Add at least `flutter build apk --debug` or a release build smoke check.

### 29. Dependencies Need A Planned Upgrade Pass

Severity: Low

Evidence:
- `flutter pub outdated` reports constrained or locked older direct dependencies including `file_picker`, `share_plus`, and `xml`.

Impact:
- Delayed upgrades can make future platform compatibility work harder.

Suggested fix:
- Schedule a dependency upgrade branch.
- Upgrade major packages with focused regression tests for import/export, sharing, and picker flows.

### 30. Informational Pages Have Fixed Rows That Can Overflow

Severity: Low

Evidence:
- About and Instructions screens use fixed card rows and unwrapped titles/tech details.

Impact:
- Long text, localization, or larger text can overflow.

Suggested fix:
- Use flexible text, wrapping rows, and text-scale tests.

## Cross-Cutting Test Gaps

- Add a detector contract test that loads `assets/models/best_int8.tflite` and validates actual input/output shapes.
- Add an integration-style scan mapping test using detector-shaped output, not only hand-authored `DetectionResult`s.
- Add project storage corruption tests for bad index JSON, bad project JSON, missing files, and index rebuild.
- Add layout tests for narrow phone width, landscape height, and high text scale.
- Add accessibility tests for semantic labels and keyboard activation on primary controls.
- Add platform config checks for iOS privacy keys and macOS entitlements.

## Suggested Roadmap

### Phase 1: Make Real Scan Output Trustworthy

- Fix TFLite output parsing or re-export the model with NMS.
- Add model contract tests.
- Add barline detection.
- Expand staff-neighborhood filtering for ledger notes.
- Support model labels for key signatures and deeper flags.

### Phase 2: Protect User Data

- Make project writes atomic.
- Rebuild or repair the project index.
- Quarantine corrupt projects.
- Use collision-resistant IDs.
- Make score model lists immutable.

### Phase 3: Platform Readiness

- Add iOS privacy strings.
- Dispose TFLite interpreter in scan lifecycle.
- Add macOS file entitlements.
- Remove debug-signing fallback for release.
- Pin CI SDK and add build smoke checks.

### Phase 4: UX And Accessibility

- Replace custom `GestureDetector` buttons with Material controls.
- Add persistent scan failure/empty states.
- Make hidden actions visible.
- Add responsive behavior for drawer, profile, editor header, playback controls, and inspectors.
