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
