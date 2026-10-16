class AppFeatures {
  const AppFeatures._();

  // Presentation branch: keep classroom code available, but hide teacher/student
  // workflow from the app surface.
  static const bool classroomWorkflow = false;

  // The app names only the genre model's genres (Waltz, Kundiman, Jazz). The
  // older rule labels (Simple Melody, Children's Song, March, Classical,
  // General Piece) are kept in ScoreClassifier but hidden.
  static const bool legacyScoreLabels = false;

  // The scanner reads G and F clefs only, so the editor offers those two.
  // Alto and tenor (C clef) support stays in the code, hidden.
  static const bool cClefs = false;
}
