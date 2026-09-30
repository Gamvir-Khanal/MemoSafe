import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FlutterSecureStorage initialization mock test', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(key: 'test_key', value: 'test_value');
    final val = await storage.read(key: 'test_key');
    expect(val, equals('test_value'));
  });
}
