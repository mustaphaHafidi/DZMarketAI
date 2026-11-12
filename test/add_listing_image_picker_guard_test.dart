import 'dart:async';
import 'dart:typed_data';

import 'package:dzmarket/src/features/listings/add_listing_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _DelayedFilePicker extends FilePicker {
  final completer = Completer<FilePickerResult?>();
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    calls++;
    return completer.future;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test',
      );
    }
  });

  testWidgets('image picker ignores a second tap while it is open', (
    tester,
  ) async {
    final picker = _DelayedFilePicker();
    FilePicker.platform = picker;

    await tester.pumpWidget(const MaterialApp(home: AddListingPage()));
    await tester.pump();

    final addPhoto = find.byIcon(Icons.add_photo_alternate_outlined);
    expect(addPhoto, findsOneWidget);
    await tester.tap(addPhoto);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.hourglass_top_outlined));
    await tester.pump();
    expect(picker.calls, 1);

    picker.completer.complete(null);
    await tester.pump();
  });

  test('image removal rejects an index made stale by an earlier gesture', () {
    expect(AddListingPage.canRemovePickedFile(index: 2, count: 1), isFalse);
    expect(AddListingPage.canRemovePickedFile(index: 0, count: 1), isTrue);
  });
}
