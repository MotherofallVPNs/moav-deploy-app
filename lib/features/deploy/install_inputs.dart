import 'dart:math';

/// Pure helpers behind the install form's simplified mode.
class InstallInputs {
  InstallInputs._();

  /// Characters upstream `install.sh` accepts unquoted in the admin password
  /// (its `ni_validate` rejects quotes, `\ $ \` #` and whitespace).
  static const passwordAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';

  static const generatedLength = 20;

  /// A random admin password from a cryptographic source. The alphabet
  /// skips look-alike characters (0/O, 1/l/I) so it can be read off a phone.
  static String generatePassword({int length = generatedLength, Random? random}) {
    final rng = random ?? Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(passwordAlphabet[rng.nextInt(passwordAlphabet.length)]);
    }
    return buf.toString();
  }

  /// Let's Encrypt contact derived from the domain: `info@<domain>`, or
  /// empty when there is no domain (domainless installs need no email).
  static String defaultEmail(String domain) {
    final d = domain.trim();
    return d.isEmpty ? '' : 'info@$d';
  }
}
