String adminOwnerDisplayName({
  required String ownerId,
  required Iterable<Map<String, dynamic>> users,
}) {
  final profile = users.cast<Map<String, dynamic>?>().firstWhere(
    (user) => user?['id']?.toString() == ownerId,
    orElse: () => null,
  );
  final fullName = profile?['full_name']?.toString().trim() ?? '';
  if (fullName.isNotEmpty) return fullName;
  final email = profile?['email']?.toString().trim() ?? '';
  if (email.isNotEmpty) return email;
  return ownerId;
}
