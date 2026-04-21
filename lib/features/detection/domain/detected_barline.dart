class DetectedBarline {
  final double x;
  final String? staffId;

  const DetectedBarline({
    required this.x,
    this.staffId,
  });

  Map<String, Object?> toJson() {
    return {
      'x': x,
      'staffId': staffId,
    };
  }

  factory DetectedBarline.fromJson(Map<String, dynamic> json) {
    return DetectedBarline(
      x: (json['x'] as num).toDouble(),
      staffId: json['staffId'] as String?,
    );
  }

  @override
  String toString() => 'DetectedBarline(${toJson()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectedBarline && other.x == x && other.staffId == staffId;
  }

  @override
  int get hashCode => Object.hash(x, staffId);
}
