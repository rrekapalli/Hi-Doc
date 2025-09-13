import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('test google sign in API', () {
    final googleSignIn = GoogleSignIn();
    // Just test that we can create the object
    expect(googleSignIn, isNotNull);
  });
}
