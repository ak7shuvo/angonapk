/// What can be reported. [apiName] is the server's `target_type`.
enum ReportTarget {
  post('post', 'post'),
  story('story', 'story'),
  comment('comment', 'comment'),
  user('user', 'profile');

  const ReportTarget(this.apiName, this.noun);
  final String apiName;

  /// Used in copy: "Report this post".
  final String noun;
}

/// Why something is being reported. [apiName] is the server's `reason`.
enum ReportReason {
  spam('spam', 'Spam or misleading', 'Ads, scams or repeated unwanted posts'),
  harassment(
    'harassment',
    'Harassment or bullying',
    'Targeting or insulting someone',
  ),
  hate('hate', 'Hate speech', 'Attacks people for who they are'),
  nudity(
    'nudity',
    'Nudity or sexual content',
    'Not suitable for a travel community',
  ),
  violence(
    'violence',
    'Violence or dangerous acts',
    'Threats, gore or harmful behaviour',
  ),
  misinformation(
    'misinformation',
    'False information',
    'Claims that are clearly untrue',
  ),
  other('other', 'Something else', 'Tell us more below');

  const ReportReason(this.apiName, this.label, this.hint);
  final String apiName;
  final String label;
  final String hint;
}
