import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/core/presentation/linkified_text.dart';

void main() {
  const announcementText = 'Voir https://example.com maintenant';

  Future<void> pumpLinkifiedText(
    WidgetTester tester, {
    required TextStyle? style,
    required Color primaryColor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.light(primary: primaryColor),
        ),
        home: Scaffold(
          body: LinkifiedText(text: announcementText, style: style),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextSpan renderedTextSpan(WidgetTester tester) {
    final richTextFinder = find.descendant(
      of: find.byType(LinkifiedText),
      matching: find.byType(RichText),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    return richText.text as TextSpan;
  }

  Iterable<TextSpan> flattenTextSpans(TextSpan rootSpan) sync* {
    yield rootSpan;
    final rootChildren = rootSpan.children;
    if (rootChildren == null) {
      return;
    }
    for (final child in rootChildren) {
      if (child is TextSpan) {
        yield* flattenTextSpans(child);
      }
    }
  }

  TextSpan findUrlSpan(TextSpan rootSpan) {
    final allSpans = flattenTextSpans(rootSpan).toList();
    return allSpans.firstWhere(
      (span) =>
          span.recognizer != null &&
          span.text != null &&
          span.text!.contains('https://example.com'),
    );
  }

  TextSpan findPlainTextSpan(TextSpan rootSpan) {
    final allSpans = flattenTextSpans(rootSpan).toList();
    return allSpans.firstWhere(
      (span) =>
          span.recognizer == null &&
          span.text != null &&
          !span.text!.contains('https://example.com'),
    );
  }

  testWidgets(
    'rebuilds spans when style changes and text is unchanged',
    (tester) async {
      const initialStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
      const updatedStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

      await pumpLinkifiedText(
        tester,
        style: initialStyle,
        primaryColor: Colors.blue,
      );

      var rootSpan = renderedTextSpan(tester);
      expect(findPlainTextSpan(rootSpan).style?.fontSize, 12);
      expect(findUrlSpan(rootSpan).style?.fontSize, 12);

      await pumpLinkifiedText(
        tester,
        style: updatedStyle,
        primaryColor: Colors.blue,
      );

      rootSpan = renderedTextSpan(tester);
      expect(findPlainTextSpan(rootSpan).style?.fontSize, 20);
      expect(findUrlSpan(rootSpan).style?.fontSize, 20);
      expect(findUrlSpan(rootSpan).style?.fontWeight, FontWeight.w700);
    },
  );

  testWidgets(
    'rebuilds spans when theme primary color changes and text is unchanged',
    (tester) async {
      await pumpLinkifiedText(
        tester,
        style: const TextStyle(fontSize: 16),
        primaryColor: Colors.blue,
      );

      var rootSpan = renderedTextSpan(tester);
      expect(findUrlSpan(rootSpan).style?.color, Colors.blue);
      expect(findUrlSpan(rootSpan).style?.decorationColor, Colors.blue);

      await pumpLinkifiedText(
        tester,
        style: const TextStyle(fontSize: 16),
        primaryColor: Colors.orange,
      );

      rootSpan = renderedTextSpan(tester);
      expect(findUrlSpan(rootSpan).style?.color, Colors.orange);
      expect(findUrlSpan(rootSpan).style?.decorationColor, Colors.orange);
    },
  );
}
