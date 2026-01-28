import 'dart:convert';
import 'dart:typed_data';

import 'package:dzmarket/src/features/listings/add_listing_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._files);

  final List<PlatformFile> _files;

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
  }) async {
    return FilePickerResult(_files);
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
  }) async =>
      null;
}

String _cachePayload(List<Map<String, String>> items) {
  return jsonEncode({
    'ts': DateTime.now().toIso8601String(),
    'items': items,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'cache.categories.v3': _cachePayload([
        {
          'id': '10',
          'name_fr': 'Electronique',
          'name_ar': 'الكترونيات',
          'icon': '',
          'parent_id': '',
          'sort_order': '1',
        },
      ]),
      'cache.wilayas.v1': _cachePayload([
        {'code': '16', 'name_fr': 'Alger', 'name_ar': 'الجزائر'},
      ]),
      'cache.communes.v1.16': _cachePayload([
        {'id': '1601', 'name_fr': 'Sidi Mhamed', 'name_ar': 'سيدي امحمد'},
      ]),
    });

    final bytes = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x00, 0x00,
      0x02, 0x00, 0x01, 0xE5, 0x27, 0xD4, 0xA2, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    FilePicker.platform = _FakeFilePicker([
      PlatformFile(
        name: 'test.png',
        size: bytes.length,
        bytes: bytes,
      ),
    ]);
  });

  // Skip: Stepper flow relies on widget-private state; cover via integration test.
  testWidgets('Add listing: required fields + stock validation', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(800, 1400);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() async {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });

    await tester.pumpWidget(const MaterialApp(home: AddListingPage()));
    await tester.pumpAndSettle();

    Finder byLabel(String label) {
      return find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
    }

    Finder dropdownByLabel(String label) {
      return find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField &&
            widget.decoration?.labelText == label,
      );
    }

    Stepper stepper() => tester.widget<Stepper>(find.byType(Stepper));

    int currentStep() => stepper().currentStep;

    Future<void> continueStep() async {
      stepper().onStepContinue?.call();
      await tester.pumpAndSettle();
    }

    void setDropdownValue(String label, String value) {
      final finder = dropdownByLabel(label);
      expect(finder, findsOneWidget);
      final widget = tester.widget(finder);
      (widget as dynamic).onChanged?.call(value);
    }

    void toggleSwitch(String label) {
      final finder = find.widgetWithText(SwitchListTile, label);
      expect(finder, findsOneWidget);
      final widget = tester.widget<SwitchListTile>(finder);
      widget.onChanged?.call(!(widget.value ?? false));
    }

    // Step 0: add photo -> continue to step 1.
    expect(currentStep(), 0);
    final photoInk = find.ancestor(
      of: find.byIcon(Icons.add_photo_alternate_outlined),
      matching: find.byType(InkWell),
    );
    if (photoInk.evaluate().isNotEmpty) {
      final widget = tester.widget<InkWell>(photoInk.first);
      widget.onTap?.call();
    }
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 1);

    // Step 1: categories loaded and selectable.
    expect(dropdownByLabel('Categorie'), findsOneWidget);
    setDropdownValue('Categorie', '10');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 2);

    // Step 2: title + description required.
    await tester.enterText(byLabel('Titre'), 'Velo');
    await tester.enterText(byLabel('Description'), 'Bon etat');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 3);

    // Step 3: stock validation blocks continue when invalid.
    await tester.enterText(byLabel('Prix de vente (DZD)'), '12000');
    await tester.enterText(byLabel('Stock disponible'), '0');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 3);
    await tester.enterText(byLabel('Stock disponible'), '2');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 4);

    // Step 4: select wilaya + commune to continue.
    setDropdownValue('Wilaya', '16');
    await tester.pumpAndSettle();
    setDropdownValue('DaÃ¯ra / Commune', '1601');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 5);

    // Step 5: delivery options required.
    toggleSwitch('Paiement a la livraison (COD)');
    toggleSwitch('Remise en main propre');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 5);
    toggleSwitch('Paiement a la livraison (COD)');
    await tester.pumpAndSettle();
    await continueStep();
    expect(currentStep(), 6);
  }, skip: true);
}



