import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/editor/domain/model/musical_symbol.dart';
import 'package:note_vision/features/editor/presentation/widgets/palette/music_symbol_palette.dart';
import 'package:note_vision/features/editor/presentation/widgets/palette/palette_item.dart';

void main() {
  testWidgets('renders all supported palette symbols and labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MusicSymbolPalette(),
        ),
      ),
    );

    expect(find.byType(PaletteItem), findsNWidgets(7));
    expect(find.text('Whole'), findsOneWidget);
    expect(find.text('Half'), findsOneWidget);
    expect(find.text('Quarter'), findsOneWidget);
    expect(find.text('Eighth'), findsOneWidget);
    expect(find.text('W Rest'), findsOneWidget);
    expect(find.text('H Rest'), findsOneWidget);
    expect(find.text('Q Rest'), findsOneWidget);
  });

  testWidgets('uses horizontal scrolling and dark themed container', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MusicSymbolPalette(),
        ),
      ),
    );

    final scrollView = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scrollView.scrollDirection, Axis.horizontal);

    final paletteContainer = tester.widget<Container>(find.byType(Container).first);
    final decoration = paletteContainer.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF1A1A1A));
    final border = decoration.border as Border;
    expect(border.top.color, const Color(0xFF2C2C2C));
  });

  testWidgets('palette item drag affordance and label legibility match spec', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaletteItem(symbol: MusicalSymbol.wholeNote),
        ),
      ),
    );

    final draggable = tester.widget<LongPressDraggable<MusicalSymbol>>(
      find.byType(LongPressDraggable<MusicalSymbol>),
    );
    final feedbackTransform = draggable.feedback as Transform;
    expect(feedbackTransform.transform.getMaxScaleOnAxis(), closeTo(1.5, 0.001));

    final draggingGhost = draggable.childWhenDragging as Opacity;
    expect(draggingGhost.opacity, 0.32);

    final label = tester.widget<Text>(find.text('Whole'));
    expect(label.style?.fontSize, 10);
    expect(label.style?.color, const Color(0xFF8A8A8A));
  });
}
