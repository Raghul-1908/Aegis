class LinkRisk {
  final bool suspicious;
  final List<String> reasons;
  final List<String> urls;
  const LinkRisk({required this.suspicious, required this.reasons, required this.urls});
  static const none = LinkRisk(suspicious: false, reasons: [], urls: []);
}

class LinkChecker {
  static final RegExp _urlPattern = RegExp(r'((?:https?:\/\/|www\.)[^\s<>"\)\]]+)', caseSensitive: false);
  static const _protectedDomains = ['parivahan.gov.in', 'uidai.gov.in', 'incometax.gov.in', 'indiapost.gov.in', 'irctc.co.in', 'onlinesbi.sbi', 'hdfcbank.com', 'icicibank.com'];
  static const _suspiciousTlds = ['.vip', '.xyz', '.tk', '.ml', '.ga', '.cf', '.top', '.click', '.loan', '.work', '.info'];
  static const _shorteners = ['bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'is.gd', 'cutt.ly', 'rebrand.ly'];

  static LinkRisk check(String text) {
    final urls = _urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
    if (urls.isEmpty) return LinkRisk.none;
    final reasons = <String>{};
    for (final raw in urls) {
      final host = _host(raw);
      if (host == null || host.isEmpty) continue;
      if (_shorteners.any((s) => host == s || host.endsWith('.$s'))) {
        reasons.add('Uses a link shortener ($host) that hides the real destination');
      }
      if (_suspiciousTlds.any(host.endsWith)) {
        reasons.add('Unusual domain ending ($host)');
      }
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
        reasons.add('Link points to a raw IP address instead of a domain');
      }
      for (final protectedDomain in _protectedDomains) {
        final distance = _levenshtein(host, protectedDomain);
        if (distance > 0 && distance <= 2) {
          reasons.add('Domain "$host" closely mimics "$protectedDomain"');
        }
      }
    }
    return LinkRisk(suspicious: reasons.isNotEmpty, reasons: reasons.toList(), urls: urls);
  }

  static String? _host(String url) {
    try { return Uri.parse(url.contains('://') ? url : 'http://$url').host.toLowerCase(); } catch (_) { return null; }
  }

  static int _levenshtein(String a, String b) {
    final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }
}