import 'package:container/helper_pages/pin_service.dart';
import 'package:container/helper_pages/security_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('PinService sets, verifies and changes PIN locally', () async {
    expect(await PinService.isPinSet(), isFalse);

    await PinService.setPin('1234');
    expect(await PinService.isPinSet(), isTrue);
    expect(await PinService.verifyPin('1234'), isTrue);
    expect(await PinService.verifyPin('0000'), isFalse);

    // Change pin
    final changed = await PinService.changePin('1234', '5678');
    expect(changed, isTrue);
    expect(await PinService.verifyPin('5678'), isTrue);
    expect(await PinService.verifyPin('1234'), isFalse);
  });

  test('PinService.clearLocalCache clears local storage without error', () async {
    await PinService.setPin('4321');
    expect(await PinService.isPinSet(), isTrue);

    await PinService.clearLocalCache();
    // Hardware vault PIN hash is cleared from local storage
    final localHash = await SecurityService.instance.getVaultPinHash();
    expect(localHash, isNull);
  });
}
