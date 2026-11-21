import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/services/glass_support.dart';

void main() {
  test('the glass gate stays closed on the host test platform', () async {
    // GlassSupport only opens on Android 13+; tests run on the desktop
    // host, so the app must keep the Material fallback bar.
    await GlassSupport.initialize();
    expect(GlassSupport.enabled, isFalse);
  });
}
