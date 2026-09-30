import 'package:container/helper_pages/note_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UnsavedChangesSheet renders all actions for a new note', (
    WidgetTester tester,
  ) async {
    UnsavedAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  chosenAction = await showModalBottomSheet<UnsavedAction>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const UnsavedChangesSheet(isNewNote: true),
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    // Open bottom sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify sheet contents
    expect(find.text('Unsaved Changes'), findsOneWidget);
    expect(
      find.text(
        'You have unsaved changes in this new note. Do you want to save it before leaving?',
      ),
      findsOneWidget,
    );
    expect(find.text('Save & Exit'), findsOneWidget);
    expect(find.text("Don't Save"), findsOneWidget);
    expect(find.text('Keep Editing'), findsOneWidget);

    // Tap Keep Editing
    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();

    expect(chosenAction, equals(UnsavedAction.cancel));
  });

  testWidgets('UnsavedChangesSheet returns save action on Save & Exit tap', (
    WidgetTester tester,
  ) async {
    UnsavedAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  chosenAction = await showModalBottomSheet<UnsavedAction>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const UnsavedChangesSheet(isNewNote: false),
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'You have unsaved modifications. Do you want to save your changes before leaving?',
      ),
      findsOneWidget,
    );

    // Tap Save & Exit
    await tester.tap(find.text('Save & Exit'));
    await tester.pumpAndSettle();

    expect(chosenAction, equals(UnsavedAction.save));
  });

  testWidgets('UnsavedChangesSheet returns discard action on Don\'t Save tap', (
    WidgetTester tester,
  ) async {
    UnsavedAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  chosenAction = await showModalBottomSheet<UnsavedAction>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const UnsavedChangesSheet(isNewNote: false),
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Tap Don't Save
    await tester.tap(find.text("Don't Save"));
    await tester.pumpAndSettle();

    expect(chosenAction, equals(UnsavedAction.discard));
  });
}
