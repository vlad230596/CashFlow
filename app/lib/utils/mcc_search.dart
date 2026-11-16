/// Reference MCC codes matching a typed query: a code prefix (1–4 digits),
/// or words of the title once at least three letters are typed. Shared by the
/// Benefit search and the payment MCC field.
List<T> searchMccCodes<T>(
  Iterable<T> items,
  String query, {
  required String Function(T item) code,
  required String Function(T item) title,
  int limit = 8,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const [];
  final digits = RegExp(r'^\d{1,4}$').hasMatch(normalized);
  if (!digits && normalized.length < 3) return const [];
  return items
      .where(
        (item) => digits
            ? code(item).startsWith(normalized)
            : title(item).toLowerCase().contains(normalized),
      )
      .take(limit)
      .toList();
}
