/// PII Scrubber — Removes personally identifiable information from telemetry.
///
/// Patterns matched:
/// - Email addresses
/// - Phone numbers
/// - Credit card numbers
/// - SSN (US)
/// - IP addresses
/// - Physical addresses (basic)
class PiiScrubber {
  const PiiScrubber();

  /// Scrub PII from text string
  String scrub(String text) {
    if (text.isEmpty) return text;

    String result = text;

    // Scrub email addresses
    result = _scrubEmails(result);

    // Scrub phone numbers
    result = _scrubPhoneNumbers(result);

    // Scrub credit card numbers
    result = _scrubCreditCards(result);

    // Scrub SSN
    result = _scrubSSN(result);

    // Scrub IP addresses
    result = _scrubIPAddresses(result);

    return result;
  }

  /// Scrub email addresses - replace with ***@email.com
  String _scrubEmails(String text) {
    // Email pattern: local@domain.tld
    final emailPattern = RegExp(
      r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
      caseSensitive: false,
    );

    return text.replaceAllMapped(emailPattern, (match) => '***@email.com');
  }

  /// Scrub phone numbers - replace with ***-***-****
  String _scrubPhoneNumbers(String text) {
    // Match various phone formats:
    // - (123) 456-7890
    // - 123-456-7890
    // - 123.456.7890
    // - 1234567890
    // - +1 123 456 7890
    final phonePatterns = [
      // US format with parentheses
      RegExp(r'\(\d{3}\)\s?\d{3}[-.\s]?\d{4}'),
      // 10 digit with separators
      RegExp(r'\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b'),
      // 10 digit continuous
      RegExp(r'\b\d{10}\b'),
      // International format
      RegExp(r'\+\d{1,3}[\s-]?\(?\d{1,4}\)?[\s-]?\d{1,4}[\s-]?\d{1,4}[\s-]?\d{1,9}'),
    ];

    String result = text;
    for (final pattern in phonePatterns) {
      result = result.replaceAllMapped(pattern, (match) => '***-***-****');
    }
    return result;
  }

  /// Scrub credit card numbers - replace with ****-****-****-****
  String _scrubCreditCards(String text) {
    // Match credit card numbers (13-19 digits)
    // May have spaces or dashes as separators
    final ccPattern = RegExp(
      r'\b(?:\d[ -]*?){13,19}\b',
    );

    return text.replaceAllMapped(ccPattern, (match) {
      final matched = match.group(0) ?? '';
      // Only replace if it looks like a credit card (passes Luhn check or has separators)
      if (_looksLikeCreditCard(matched)) {
        return '****-****-****-****';
      }
      return matched;
    });
  }

  /// Basic credit card validation using Luhn algorithm
  bool _looksLikeCreditCard(String number) {
    // Remove spaces and dashes
    final clean = number.replaceAll(RegExp(r'[^\d]'), '');

    // Credit cards are 13-19 digits
    if (clean.length < 13 || clean.length > 19) {
      return false;
    }

    // If it has separators (spaces or dashes), it's more likely to be a card
    final hasSeparators = number.contains(' ') || number.contains('-');
    if (hasSeparators) {
      return true;
    }

    // Check Luhn algorithm for continuous numbers
    return _luhnCheck(clean);
  }

  bool _luhnCheck(String cardNumber) {
    int sum = 0;
    bool alternate = false;

    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);

      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }

      sum += digit;
      alternate = !alternate;
    }

    return sum % 10 == 0;
  }

  /// Scrub SSN - replace with ***-**-****
  String _scrubSSN(String text) {
    // SSN formats: 123-45-6789 or 123 45 6789 or 123456789
    final ssnPatterns = [
      RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
      RegExp(r'\b\d{3}\s\d{2}\s\d{4}\b'),
      RegExp(r'\b\d{9}\b'), // Only if all 9 digits (risky)
    ];

    String result = text;
    for (final pattern in ssnPatterns) {
      result = result.replaceAllMapped(pattern, (match) => '***-**-****');
    }
    return result;
  }

  /// Scrub IP addresses - replace with ***.***.***.***
  String _scrubIPAddresses(String text) {
    // IPv4 pattern
    final ipv4Pattern = RegExp(
      r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b',
    );

    return text.replaceAllMapped(ipv4Pattern, (match) => '***.***.***.***');
  }

  /// Scrub address patterns - replace with [ADDRESS]
  String scrubAddress(String text) {
    // Basic address patterns
    final addressPatterns = [
      // Street addresses (number + street name)
      RegExp(r'\d+\s+[A-Z][a-z]+\s+(Street|St|Avenue|Ave|Road|Rd|Lane|Ln|Drive|Dr|Boulevard|Blvd|Court|Ct|Place|Pl)', caseSensitive: false),
      // ZIP codes
      RegExp(r'\b\d{5}(?:-\d{4})?\b'),
      // City, State format
      RegExp(r'[A-Z][a-z]+,\s*[A-Z]{2}\s*\d{5}', caseSensitive: false),
    ];

    String result = text;
    for (final pattern in addressPatterns) {
      result = result.replaceAllMapped(pattern, (match) => '[ADDRESS]');
    }
    return result;
  }

  /// Scrub all sensitive data from a map
  Map<String, dynamic> scrubMap(Map<String, dynamic> data) {
    final scrubbed = <String, dynamic>{};

    data.forEach((key, value) {
      // Check for known sensitive keys
      final lowerKey = key.toLowerCase();
      final isSensitiveKey = _sensitiveKeys.contains(lowerKey) ||
          lowerKey.contains('password') ||
          lowerKey.contains('secret') ||
          lowerKey.contains('token') ||
          lowerKey.contains('api_key') ||
          lowerKey.contains('apikey');

      if (isSensitiveKey && value is String) {
        scrubbed[key] = '***REDACTED***';
      } else if (value is String) {
        scrubbed[key] = scrub(value);
      } else if (value is Map) {
        scrubbed[key] = scrubMap(value.cast<String, dynamic>());
      } else if (value is List) {
        scrubbed[key] = _scrubList(value);
      } else {
        scrubbed[key] = value;
      }
    });

    return scrubbed;
  }

  List<dynamic> _scrubList(List list) {
    return list.map((item) {
      if (item is String) {
        return scrub(item);
      } else if (item is Map) {
        return scrubMap(item.cast<String, dynamic>());
      } else if (item is List) {
        return _scrubList(item);
      }
      return item;
    }).toList();
  }

  /// Keys that commonly contain sensitive data
  static const Set<String> _sensitiveKeys = {
    'email',
    'phonenumber',
    'phone',
    'mobile',
    'ssn',
    'socialsecurity',
    'creditcard',
    'cardnumber',
    'card_number',
    'cvv',
    'cvc',
    'address',
    'zipcode',
    'zip',
    'postalcode',
    'ip',
    'ipaddress',
    'firstname',
    'lastname',
    'fullname',
    'name',
    'dob',
    'birth_date',
    'accountnumber',
    'account_number',
    'routingnumber',
    'routing_number',
  };
}
