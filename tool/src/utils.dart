// General utility functions for the build tool

/// Compare semantic version strings (e.g., "27.0.12077973" vs "26.3.11579264")
/// 
/// Returns:
/// - Positive value if [a] > [b]
/// - Negative value if [a] < [b]
/// - Zero if [a] == [b]
/// 
/// Handles versions with any number of parts (e.g., "1.2", "1.2.3", "1.2.3.4").
/// Missing parts are treated as 0 (e.g., "1.2" vs "1.2.0" are equal).
int compareVersions(String a, String b) {
  final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  
  // Compare all parts, using the longer version's length
  final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < maxLen; i++) {
    final aVal = i < aParts.length ? aParts[i] : 0;
    final bVal = i < bParts.length ? bParts[i] : 0;
    if (aVal != bVal) return aVal.compareTo(bVal);
  }
  return 0;
}
