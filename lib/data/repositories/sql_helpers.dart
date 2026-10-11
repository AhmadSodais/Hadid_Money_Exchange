/// Helpers shared by SQLite repository implementations.
int? firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return null;
  final value = rows.first.values.firstOrNull;
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
