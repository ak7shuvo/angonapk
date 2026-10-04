/// Parser for the story body format (stored as plain text on the server):
///
///   paragraphs separated by blank lines
///   `## Heading`
///   `> A pull quote`
///   `![caption](asset:<uuid>)`   — an uploaded image
sealed class StoryBlock {
  const StoryBlock();
}

class ParagraphBlock extends StoryBlock {
  const ParagraphBlock(this.text);
  final String text;
}

class HeadingBlock extends StoryBlock {
  const HeadingBlock(this.text);
  final String text;
}

class QuoteBlock extends StoryBlock {
  const QuoteBlock(this.text);
  final String text;
}

class ImageBlock extends StoryBlock {
  const ImageBlock(this.assetId, this.caption);
  final String assetId;
  final String caption;
}

final _image = RegExp(r'^!\[([^\]]*)\]\(asset:([0-9a-fA-F-]{36})\)$');

List<StoryBlock> parseStory(String content) {
  final blocks = <StoryBlock>[];
  for (final raw in content.split(RegExp(r'\n\s*\n'))) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    final image = _image.firstMatch(text);
    if (image != null) {
      blocks.add(ImageBlock(image.group(2)!, image.group(1)!.trim()));
    } else if (text.startsWith('## ')) {
      blocks.add(HeadingBlock(text.substring(3).trim()));
    } else if (text.startsWith('>')) {
      final quote = text
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^>\s?'), ''))
          .join('\n')
          .trim();
      blocks.add(QuoteBlock(quote));
    } else {
      blocks.add(ParagraphBlock(text));
    }
  }
  return blocks;
}

/// Token to insert into the editor for an uploaded image.
String imageToken(String assetId, [String caption = '']) =>
    '![${caption.replaceAll(RegExp(r'[\[\]\n]'), ' ').trim()}](asset:$assetId)';

/// Result of an editing helper: new text and where the caret should be.
class EditResult {
  const EditResult(this.text, this.caret);
  final String text;
  final int caret;
}

/// Toggles [prefix] (e.g. `## ` or `> `) on the line containing [caret].
EditResult toggleLinePrefix(String text, int caret, String prefix) {
  final pos = caret.clamp(0, text.length);
  final start = text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1) + 1;
  final lineStart = pos == 0 ? 0 : start;
  final end = text.indexOf('\n', lineStart);
  final lineEnd = end == -1 ? text.length : end;
  final line = text.substring(lineStart, lineEnd);
  if (line.startsWith(prefix)) {
    return EditResult(
      text.replaceRange(lineStart, lineStart + prefix.length, ''),
      (pos - prefix.length).clamp(lineStart, text.length),
    );
  }
  return EditResult(
    text.replaceRange(lineStart, lineStart, prefix),
    pos + prefix.length,
  );
}

/// Inserts [block] as its own paragraph at [caret].
EditResult insertBlock(String text, int caret, String block) {
  final pos = caret.clamp(0, text.length);
  final before = text.substring(0, pos);
  final after = text.substring(pos);
  final lead = before.isEmpty || before.endsWith('\n\n')
      ? ''
      : (before.endsWith('\n') ? '\n' : '\n\n');
  final trail = after.isEmpty || after.startsWith('\n\n')
      ? ''
      : (after.startsWith('\n') ? '\n' : '\n\n');
  final inserted = '$lead$block$trail';
  return EditResult('$before$inserted$after', before.length + inserted.length);
}
