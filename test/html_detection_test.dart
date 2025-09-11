import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HTML Detection Tests', () {
    bool containsHtml(String text) {
      return text.contains('<') &&
          text.contains('>') &&
          (text.contains('<div') ||
              text.contains('<h') ||
              text.contains('<p') ||
              text.contains('<ul') ||
              text.contains('<li') ||
              text.contains('<strong') ||
              text.contains('<em') ||
              text.contains('class='));
    }

    test('should detect HTML content correctly', () {
      // Should detect HTML
      expect(
        containsHtml('<div class="medical-response"><h2>Test</h2></div>'),
        true,
      );
      expect(containsHtml('<p>This is a paragraph</p>'), true);
      expect(containsHtml('<ul><li>List item</li></ul>'), true);
      expect(containsHtml('<strong>Bold text</strong>'), true);
      expect(containsHtml('<em>Italic text</em>'), true);

      // Should not detect as HTML
      expect(containsHtml('Regular text message'), false);
      expect(containsHtml('Text with < and > symbols but no tags'), false);
      expect(containsHtml('Math: 5 < 10 > 3'), false);
      expect(containsHtml(''), false);
    });

    test('should handle edge cases', () {
      expect(containsHtml('<invalid>'), false);
      expect(containsHtml('< >'), false);
      expect(containsHtml('<div class="test">'), true);
      expect(containsHtml('<h2>Heading</h2>'), true);
    });
  });
}
