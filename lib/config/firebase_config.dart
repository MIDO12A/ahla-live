import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration for project `zeroappzero-e1b4a`.
///
/// Values were taken from `android/app/google-services.json`.
/// If this project uses a different Firebase project, replace these values
/// with the Web config from Firebase Console:
///   Project settings -> Your apps -> Web app -> SDK setup and configuration
class FirebaseConfig {
  static const String projectId = 'ahla-live';
  static const String apiKey = 'AIzaSyBeRauEkyFcsB7ryTYTx28aOO2szSBZjCg';
  static const String appId = '1:183199730954:android:cbf937664eb5f2fd383ef3';
  static const String messagingSenderId = '183199730954';
  static const String databaseURL = 'https://ahla-live-default-rtdb.firebaseio.com';
  static const String storageBucket = 'ahla-live.firebasestorage.app';
  static const String authDomain = 'ahla-live.firebaseapp.com';

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    databaseURL: databaseURL,
    storageBucket: storageBucket,
    authDomain: authDomain,
  );

  /// The project id of the Firebase project (used for Firestore/Storage rules).
  static String get project => projectId;
}
