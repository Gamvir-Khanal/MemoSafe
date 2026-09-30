// File generated for safememo-a3afa Firebase project.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA6g1HYvNC6lzqR3mZvoINeNMrHxmbTgBo',
    appId: '1:350678445893:android:03716064666522cec1182c',
    messagingSenderId: '350678445893',
    projectId: 'safememo-a3afa',
    authDomain: 'safememo-a3afa.firebaseapp.com',
    storageBucket: 'safememo-a3afa.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA6g1HYvNC6lzqR3mZvoINeNMrHxmbTgBo',
    appId: '1:350678445893:android:03716064666522cec1182c',
    messagingSenderId: '350678445893',
    projectId: 'safememo-a3afa',
    storageBucket: 'safememo-a3afa.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA6g1HYvNC6lzqR3mZvoINeNMrHxmbTgBo',
    appId: '1:350678445893:android:03716064666522cec1182c',
    messagingSenderId: '350678445893',
    projectId: 'safememo-a3afa',
    storageBucket: 'safememo-a3afa.firebasestorage.app',
    iosBundleId: 'com.example.memoApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA6g1HYvNC6lzqR3mZvoINeNMrHxmbTgBo',
    appId: '1:350678445893:android:03716064666522cec1182c',
    messagingSenderId: '350678445893',
    projectId: 'safememo-a3afa',
    storageBucket: 'safememo-a3afa.firebasestorage.app',
    iosBundleId: 'com.example.memoApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA6g1HYvNC6lzqR3mZvoINeNMrHxmbTgBo',
    appId: '1:350678445893:android:03716064666522cec1182c',
    messagingSenderId: '350678445893',
    projectId: 'safememo-a3afa',
    authDomain: 'safememo-a3afa.firebaseapp.com',
    storageBucket: 'safememo-a3afa.firebasestorage.app',
  );
}
