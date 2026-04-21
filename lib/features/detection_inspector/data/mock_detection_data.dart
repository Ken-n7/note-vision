// lib/features/dev/data/mock_detection_data.dart

const String kMockDetectionCase1 = '''
{
  "imageId": "mock-case-01",
  "staffs": [
    {
      "id": "staff-1",
      "topY": 100.0,
      "bottomY": 160.0,
      "lineYs": [100.0, 115.0, 130.0, 145.0, 160.0]
    }
  ],
  "barlines": [
    { "x": 80.0,  "staffId": "staff-1" },
    { "x": 280.0, "staffId": "staff-1" },
    { "x": 480.0, "staffId": "staff-1" }
  ],
  "symbols": [
    { "id": "s01", "type": "gClef",        "x": 20.0,  "y": 95.0,  "width": 24.0, "height": 72.0, "confidence": 0.97 },
    { "id": "s02", "type": "timeSig4",     "x": 50.0,  "y": 100.0, "width": 14.0, "height": 30.0, "confidence": 0.93 },
    { "id": "s03", "type": "timeSig4",     "x": 50.0,  "y": 130.0, "width": 14.0, "height": 30.0, "confidence": 0.91 },
    { "id": "s04", "type": "noteheadBlack","x": 90.0,  "y": 148.0, "width": 12.0, "height": 10.0, "confidence": 0.88 },
    { "id": "s05", "type": "stem",         "x": 101.0, "y": 108.0, "width": 2.0,  "height": 48.0, "confidence": 0.95 },
    { "id": "s06", "type": "noteheadBlack","x": 130.0, "y": 138.0, "width": 12.0, "height": 10.0, "confidence": 0.84 },
    { "id": "s07", "type": "stem",         "x": 141.0, "y": 100.0, "width": 2.0,  "height": 46.0, "confidence": 0.92 },
    { "id": "s08", "type": "noteheadHalf", "x": 170.0, "y": 143.0, "width": 14.0, "height": 10.0, "confidence": 0.90 },
    { "id": "s09", "type": "stem",         "x": 183.0, "y": 103.0, "width": 2.0,  "height": 48.0, "confidence": 0.93 },
    { "id": "s10", "type": "restQuarter",  "x": 210.0, "y": 118.0, "width": 12.0, "height": 22.0, "confidence": 0.86 },
    { "id": "s11", "type": "noteheadBlack","x": 300.0, "y": 133.0, "width": 12.0, "height": 10.0, "confidence": 0.82 },
    { "id": "s12", "type": "stem",         "x": 311.0, "y": 95.0,  "width": 2.0,  "height": 46.0, "confidence": 0.90 },
    { "id": "s13", "type": "flag8thUp",    "x": 312.0, "y": 92.0,  "width": 14.0, "height": 18.0, "confidence": 0.78 },
    { "id": "s14", "type": "noteheadWhole","x": 340.0, "y": 148.0, "width": 16.0, "height": 10.0, "confidence": 0.95 },
    { "id": "s15", "type": "restHalf",     "x": 380.0, "y": 120.0, "width": 18.0, "height": 10.0, "confidence": 0.87 },
    { "id": "s16", "type": "noteheadBlack","x": 420.0, "y": 128.0, "width": 12.0, "height": 10.0, "confidence": 0.80 },
    { "id": "s17", "type": "stem",         "x": 431.0, "y": 90.0,  "width": 2.0,  "height": 46.0, "confidence": 0.88 }
  ]
}
''';

const String kMockDetectionCase2 = '''
{
  "imageId": "mock-case-02-warnings",
  "staffs": [],
  "barlines": [],
  "symbols": [
    { "id": "s01", "type": "noteheadBlack", "x": 50.0, "y": 100.0, "width": 12.0, "height": 10.0, "confidence": 0.75 }
  ]
}
''';

const String kMockDetectionCase3 = '''
{
  "imageId": "mock-case-03-multi-measure",
  "staffs": [
    {
      "id": "staff-1",
      "topY": 80.0,
      "bottomY": 140.0,
      "lineYs": [80.0, 95.0, 110.0, 125.0, 140.0]
    }
  ],
  "barlines": [
    { "x": 60.0,  "staffId": "staff-1" },
    { "x": 200.0, "staffId": "staff-1" },
    { "x": 340.0, "staffId": "staff-1" },
    { "x": 480.0, "staffId": "staff-1" }
  ],
  "symbols": [
    { "id": "s01", "type": "gClef",         "x": 10.0,  "y": 75.0,  "width": 24.0, "height": 70.0, "confidence": 0.98 },
    { "id": "s02", "type": "noteheadWhole",  "x": 80.0,  "y": 130.0, "width": 16.0, "height": 10.0, "confidence": 0.92 },
    { "id": "s03", "type": "noteheadHalf",   "x": 130.0, "y": 120.0, "width": 14.0, "height": 10.0, "confidence": 0.88 },
    { "id": "s04", "type": "stem",           "x": 143.0, "y": 82.0,  "width": 2.0,  "height": 46.0, "confidence": 0.91 },
    { "id": "s05", "type": "restQuarter",    "x": 165.0, "y": 100.0, "width": 12.0, "height": 22.0, "confidence": 0.84 },
    { "id": "s06", "type": "noteheadBlack",  "x": 220.0, "y": 125.0, "width": 12.0, "height": 10.0, "confidence": 0.85 },
    { "id": "s07", "type": "stem",           "x": 231.0, "y": 85.0,  "width": 2.0,  "height": 48.0, "confidence": 0.90 },
    { "id": "s08", "type": "flag8thUp",      "x": 232.0, "y": 82.0,  "width": 14.0, "height": 18.0, "confidence": 0.77 },
    { "id": "s09", "type": "noteheadBlack",  "x": 270.0, "y": 115.0, "width": 12.0, "height": 10.0, "confidence": 0.82 },
    { "id": "s10", "type": "stem",           "x": 281.0, "y": 77.0,  "width": 2.0,  "height": 46.0, "confidence": 0.89 },
    { "id": "s11", "type": "restHalf",       "x": 310.0, "y": 102.0, "width": 18.0, "height": 10.0, "confidence": 0.86 },
    { "id": "s12", "type": "noteheadHalf",   "x": 360.0, "y": 130.0, "width": 14.0, "height": 10.0, "confidence": 0.89 },
    { "id": "s13", "type": "stem",           "x": 373.0, "y": 90.0,  "width": 2.0,  "height": 48.0, "confidence": 0.93 },
    { "id": "s14", "type": "noteheadBlack",  "x": 410.0, "y": 120.0, "width": 12.0, "height": 10.0, "confidence": 0.81 },
    { "id": "s15", "type": "stem",           "x": 421.0, "y": 80.0,  "width": 2.0,  "height": 48.0, "confidence": 0.87 },
    { "id": "s16", "type": "restWhole",      "x": 455.0, "y": 100.0, "width": 18.0, "height": 8.0,  "confidence": 0.90 }
  ]
}
''';
