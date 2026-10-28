/// Where the in-app links go. One place to change when a URL moves.
class MoavLinks {
  MoavLinks._();

  static final docs = Uri.parse('https://moav.sh/docs');

  // TODO: confirm the exact support/donate page with the project owner.
  static final support = Uri.parse(supportUrl);
  static const supportUrl = 'https://moav.sh/support';

  static final github = Uri.parse('https://github.com/MotherofallVPNs');
  static final x = Uri.parse('https://x.com/motherofallvpns');
  static final telegram = Uri.parse('https://t.me/motherofallvpns');

  /// This app's source and its releases (APK, AAB and SHA256SUMS).
  static const repoUrl = 'https://github.com/MotherofallVPNs/moav-deploy-app';
  static final repo = Uri.parse(repoUrl);
  static final releases = Uri.parse('$repoUrl/releases');
}
