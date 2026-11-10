/// Where the in-app links go. One place to change when a URL moves.
class MoavLinks {
  MoavLinks._();

  static final docs = Uri.parse('https://moav.sh/docs');

  /// Which records a domain install needs and how to verify them.
  static final docsDns = Uri.parse('https://moav.sh/docs/DNS/');

  /// Money donations (the "Support us" popup). Dart spelling of the
  /// SUPPORT_GITHUB_SPONSORS_URL / SUPPORT_BUYMEACOFFEE_URL constants.
  static const supportGithubSponsorsUrl =
      'https://github.com/sponsors/shayanb';

  static const supportBuymeacoffeeUrl = 'https://buymeacoffee.com/pangana';

  /// One-time donation via Stripe Checkout (Apple Pay / Google Pay, cards).
  static const supportDonateUrl = 'https://buy.stripe.com/6oU9AT96x8t21xX3Wc5c400';

  /// Every other way to help: translations, servers, code, spreading the word.
  static const supportMoreUrl = 'https://moav.sh/docs/support/';

  static final supportDonate = Uri.parse(supportDonateUrl);
  static final supportGithubSponsors = Uri.parse(supportGithubSponsorsUrl);
  static final supportBuymeacoffee = Uri.parse(supportBuymeacoffeeUrl);
  static final supportMore = Uri.parse(supportMoreUrl);

  static final github = Uri.parse('https://github.com/MotherofallVPNs');
  static final x = Uri.parse('https://x.com/motherofallvpns');
  static final telegram = Uri.parse('https://t.me/motherofallvpns');

  /// This app's source and its releases (APK, AAB and SHA256SUMS).
  static const repoUrl = 'https://github.com/MotherofallVPNs/moav-deploy-app';
  static final repo = Uri.parse(repoUrl);
  static final releases = Uri.parse('$repoUrl/releases');
}
