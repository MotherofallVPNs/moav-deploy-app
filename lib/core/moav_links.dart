/// Where the in-app links go. One place to change when a URL moves.
class MoavLinks {
  MoavLinks._();

  static final docs = Uri.parse('https://moav.sh/docs');

  /// Money donations (the "Support us" popup). Dart spelling of the
  /// SUPPORT_GITHUB_SPONSORS_URL / SUPPORT_BUYMEACOFFEE_URL constants.
  // TODO: confirm the GitHub Sponsors handle with the project owner.
  static const supportGithubSponsorsUrl =
      'https://github.com/sponsors/MotherofallVPNs';

  // TODO: confirm the Buy Me a Coffee handle with the project owner.
  static const supportBuymeacoffeeUrl = 'https://buymeacoffee.com/moav';

  /// Every other way to help: translations, servers, code, spreading the word.
  static const supportMoreUrl = 'https://moav.sh/docs/support/';

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
