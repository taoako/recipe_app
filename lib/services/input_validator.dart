import 'dart:typed_data';

class InputValidator {
  InputValidator._();

  static const int maxUsernameLength = 30;
  static const int maxEmailLength = 254;
  static const int maxTitleLength = 100;
  static const int maxDescriptionLength = 2000;
  static const int maxIngredientLength = 200;
  static const int maxStepLength = 1000;
  static const int maxSearchQueryLength = 100;

  /// Maximum allowed image upload size (5 MB).
  static const int maxImageUploadBytes = 5 * 1024 * 1024;
  static const Set<String> allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  // ── Basic validators ──────────────────────────────────────────
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

  /// Validates a required text field with an optional length limit.
  static String? validateRequiredText(
    String? value,
    String fieldName, {
    int? maxLength,
  }) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return '$fieldName is required';
    }
    if (maxLength != null && normalized.length > maxLength) {
      return '$fieldName must be $maxLength characters or less';
    }
    return null;
  }

  /// Validates a positive whole-number field within an allowed range.
  static String? validatePositiveInteger(
    String? value,
    String fieldName, {
    int min = 1,
    int max = 300,
  }) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return '$fieldName is required';
    }
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      return '$fieldName must contain digits only';
    }

    final parsed = int.tryParse(normalized);
    if (parsed == null) {
      return '$fieldName must be a valid whole number';
    }
    if (parsed < min || parsed > max) {
      return '$fieldName must be between $min and $max';
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

  /// Validates password strength with strong policy requirements:
  /// - Min 8 characters
  /// - At least one uppercase letter
  /// - At least one lowercase letter
  /// - At least one digit
  /// - At least one special character
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  /// Validates uploaded image by extension, size, and file signature.
  static String? validateImageUpload({
    required String fileName,
    required int fileSizeBytes,
    Uint8List? fileBytes,
  }) {
    final extension = _extractExtension(fileName);
    if (!allowedImageExtensions.contains(extension)) {
      return 'Only JPG, PNG, or WEBP images are allowed';
    }

    if (fileSizeBytes > maxImageUploadBytes) {
      return 'Image must be 5 MB or smaller';
    }

    if (fileBytes != null && !_hasSupportedImageSignature(fileBytes)) {
      return 'Invalid image file content';
    }

    return null;
  }

  static String _extractExtension(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final lastDot = normalized.lastIndexOf('.');
    if (lastDot == -1 || lastDot == normalized.length - 1) return '';
    return normalized.substring(lastDot + 1);
  }

  static bool _hasSupportedImageSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;

    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;

    final isWebp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;

    return isJpeg || isPng || isWebp;
  }
}
