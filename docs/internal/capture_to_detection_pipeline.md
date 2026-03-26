# Capture/Import → Detection Pipeline (Updated)

## 1) Image acquisition (camera or gallery)
- `CaptureScreen` provides camera and gallery entry points.
- `ImagePickerHelper` now requests higher-fidelity capture:
  - `imageQuality: 90`
  - `maxWidth/maxHeight: 2000`
  - rear camera preferred.

## 2) Transition into pipeline
- Selected image bytes are read and passed into `ScanScreenProvider(imageBytes: bytes)`.
- `ScanScreenProvider` constructs `ScanViewModel` with:
  - `BasicImagePreprocessor()`
  - `TfliteStructureDetector()`
  - `BasicStaveAwareCropper()`
  - `TfliteSymbolDetector()`
  - `BasicSymbolRelationResolver()`

## 3) ViewModel orchestration
`ScanViewModel.run(bytes)` now executes:
1. `preprocessing` (full-page preprocess, target size 1024)
2. `detectingStructure` (structure pass)
3. `cropping` (stave-aware crop generation)
4. `detecting` (symbol detection for each crop)
5. `resolving` (relationship/pitch resolution)
6. `done` (publish `ScanResult`)

## 4) Preprocessing
- `BasicImagePreprocessor.preprocess` now accepts configurable `targetSize`.
- The full-page structure pass uses `targetSize: 1024`.
- Per-crop symbol pass uses `targetSize: 416`.

## 5) Structure detection
- `TfliteStructureDetector` attempts to load `assets/models/omr_structure.tflite`.
- If unavailable, it falls back to a baseline one-system structure.
- Output model: `ScoreStructure` (`systems`, `groups`, `staveLines`).

## 6) Stave-aware cropping
- `BasicStaveAwareCropper` returns `List<StaveCrop>` with per-stave metadata:
  - `staveIndex`, `instrumentGroup`, `offsetX`, `offsetY`, `scale`, `isBracePair`.

## 7) Symbol detection and remap
- Symbol detector runs per generated crop.
- Each `DetectedSymbol` is remapped to full-image coordinates via:
  - `DetectedSymbol.toStaveCoordinates(StaveCrop crop)`.

## 8) Relationship resolution
- `BasicSymbolRelationResolver` produces `ResolvedScore`:
  - note subset with coarse pitch labels (`high`/`mid`/`low`/`unknown`)
  - resolved symbol list.

## 9) Rendering
- `ScanResult` now carries:
  - `detection`
  - `structure`
  - `resolvedScore`
- `DetectionOverlay` now renders:
  - structure layer (`ScoreStructure.systems`)
  - symbol layer (`ResolvedScore.symbols` via `result.symbols`)

## 10) States
`ScanState` now includes:
- `idle`
- `preprocessing`
- `detectingStructure`
- `cropping`
- `detecting`
- `resolving`
- `done`
- `error`
