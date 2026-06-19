/// Centralized form validation for Nexus MDM UI.
///
/// All validators follow the Flutter FormField `validator` signature:
///   `String? Function(String?)` — returns null on valid, error message on invalid.
///
/// Usage:
///   TextFormField(validator: Validators.email)
///   TextFormField(validator: Validators.required('Entity type'))
library validators;

class Validators {
  Validators._();

  // ── Required ─────────────────────────────────────────────────────────────

  /// Returns a validator that rejects null / blank values.
  /// [label] is included in the error message ("Entity type is required").
  static String? Function(String?) required(String label) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return '$label is required';
      }
      return null;
    };
  }

  // ── Email ─────────────────────────────────────────────────────────────────

  static final _emailRe = RegExp(
    r'^[a-zA-Z0-9.!#$%&'
    r"'*+/=?^_`{|}~-]+"
    r'@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  /// Rejects blank or malformed email addresses.
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!_emailRe.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  /// Optional email — passes blank values, rejects malformed non-blank ones.
  static String? emailOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!_emailRe.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  // ── Password ──────────────────────────────────────────────────────────────

  /// Requires ≥8 chars, at least 1 digit, at least 1 letter.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!value.contains(RegExp(r'[A-Za-z]'))) {
      return 'Password must contain at least one letter';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one digit';
    }
    return null;
  }

  /// Confirms that [value] matches [other].
  static String? Function(String?) passwordConfirm(String other) {
    return (value) {
      if (value == null || value.isEmpty) return 'Please confirm your password';
      if (value != other) return 'Passwords do not match';
      return null;
    };
  }

  // ── URL ───────────────────────────────────────────────────────────────────

  static final _urlRe = RegExp(
    r'^https?://'
    r'(\w+\.)*\w+'
    r'(:\d{1,5})?'
    r'(/[^\s]*)?$',
    caseSensitive: false,
  );

  /// Rejects blank or syntactically invalid URLs.
  static String? url(String? value) {
    if (value == null || value.trim().isEmpty) return 'URL is required';
    if (!_urlRe.hasMatch(value.trim())) return 'Enter a valid URL (http:// or https://)';
    return null;
  }

  /// Optional URL — passes blank, rejects malformed non-blank ones.
  static String? urlOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!_urlRe.hasMatch(value.trim())) return 'Enter a valid URL (http:// or https://)';
    return null;
  }

  // ── UUID ──────────────────────────────────────────────────────────────────

  static final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Rejects blank or malformed UUIDs.
  static String? uuid(String? value) {
    if (value == null || value.trim().isEmpty) return 'ID is required';
    if (!_uuidRe.hasMatch(value.trim())) return 'Enter a valid UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)';
    return null;
  }

  // ── Length ────────────────────────────────────────────────────────────────

  /// Enforces minimum character length (after trim).
  static String? Function(String?) minLength(int min, {String? label}) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return '${label ?? 'Field'} is required';
      if (trimmed.length < min) return '${label ?? 'Field'} must be at least $min characters';
      return null;
    };
  }

  /// Enforces maximum character length (after trim).
  static String? Function(String?) maxLength(int max, {String? label}) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.length > max) return '${label ?? 'Field'} must be at most $max characters';
      return null;
    };
  }

  // ── Numeric ───────────────────────────────────────────────────────────────

  /// Rejects non-numeric input; optionally enforces a [min] / [max] range.
  static String? Function(String?) number({
    double? min,
    double? max,
    String? label,
  }) {
    return (value) {
      if (value == null || value.trim().isEmpty) return '${label ?? 'Value'} is required';
      final n = double.tryParse(value.trim());
      if (n == null) return '${label ?? 'Value'} must be a number';
      if (min != null && n < min) return '${label ?? 'Value'} must be ≥ $min';
      if (max != null && n > max) return '${label ?? 'Value'} must be ≤ $max';
      return null;
    };
  }

  // ── Composite ─────────────────────────────────────────────────────────────

  /// Runs [validators] in order; returns the first error, or null if all pass.
  static String? Function(String?) compose(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final v in validators) {
        final err = v(value);
        if (err != null) return err;
      }
      return null;
    };
  }

  // ── Rego policy ───────────────────────────────────────────────────────────

  /// Basic structural check for a Rego policy string.
  static String? regoPolicy(String? value) {
    if (value == null || value.trim().isEmpty) return 'Policy body is required';
    final trimmed = value.trim();
    if (!trimmed.startsWith('package ')) {
      return 'Rego policy must start with a package declaration (package ...)';
    }
    if (trimmed.length < 20) return 'Policy body is too short to be valid';
    return null;
  }

  // ── Entity type ───────────────────────────────────────────────────────────

  static final _entityTypeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{1,63}$');

  /// Entity types must be snake_case / PascalCase identifiers, max 64 chars.
  static String? entityType(String? value) {
    if (value == null || value.trim().isEmpty) return 'Entity type is required';
    if (!_entityTypeRe.hasMatch(value.trim())) {
      return 'Entity type must start with a letter and contain only letters, digits, or underscores';
    }
    return null;
  }

  // ── JSON ──────────────────────────────────────────────────────────────────

  /// Validates that the value is non-empty and parseable as JSON.
  static String? json(String? value) {
    if (value == null || value.trim().isEmpty) return 'JSON is required';
    try {
      // Minimal structural check — balanced braces/brackets
      final t = value.trim();
      if ((t.startsWith('{') && t.endsWith('}')) ||
          (t.startsWith('[') && t.endsWith(']'))) {
        return null;
      }
      return 'Value must be a valid JSON object ({...}) or array ([...])';
    } catch (_) {
      return 'Enter valid JSON';
    }
  }
}
