/// Utility helpers for input validation and sanitization.
class InputValidator {
  InputValidator._();

  /// Maximum allowed length for a username.
  static const int maxUsernameLength = 30;

  /// Maximum allowed length for an email address.
  static const int maxEmailLength = 254;

  /// Maximum allowed length for a recipe title.
  static const int maxTitleLength = 100;

  /// Maximum allowed length for a description.
  static const int maxDescriptionLength = 2000;

  /// Maximum allowed length for a single ingredient.
  static const int maxIngredientLength = 200;

  /// Maximum allowed length for a single step description.
  static const int maxStepLength = 1000;

  /// Maximum allowed length for a search query.
  static const int maxSearchQueryLength = 100;

  // ── Basic validators ──────────────────────────────────────────

  /// Returns `true` when [value] looks like a valid Firestore document ID
  /// (non-empty, alphanumeric with limited special chars, max 128 chars).
  static bool isValidDocumentId(String? value) {
    if (value == null || value.isEmpty || value.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(value);
  }

  /// Validates email format using a simple but reasonable regex.
  static bool isValidEmail(String? value) {
    if (value == null || value.isEmpty || value.length > maxEmailLength) {
      return false;
    }
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  /// Validates username: non-empty, within length limit, no special chars.
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (value.trim().length > maxUsernameLength) {
      return 'Username must be $maxUsernameLength characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_.\- ]+$').hasMatch(value.trim())) {
      return 'Username contains invalid characters';
    }
    return null; // valid
  }

  /// Validates a recipe title.
  static String? validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Title is required';
    }
    if (value.trim().length > maxTitleLength) {
      return 'Title must be $maxTitleLength characters or less';
    }
    return null;
  }

  /// Validates a description field.
  static String? validateDescription(String? value) {
    if (value != null && value.trim().length > maxDescriptionLength) {
      return 'Description must be $maxDescriptionLength characters or less';
    }
    return null;
  }

  /// Sanitizes a string by trimming and limiting its length.
  static String sanitize(String input, int maxLength) {
    final trimmed = input.trim();
    if (trimmed.length > maxLength) {
      return trimmed.substring(0, maxLength);
    }
    return trimmed;
  }

  /// Validates a search query.
  static String? validateSearchQuery(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Search query cannot be empty';
    }
    if (value.trim().length > maxSearchQueryLength) {
      return 'Search query is too long';
    }
    return null;
  }

  /// Validates password strength: min 6 chars (Firebase Auth minimum).
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
}
