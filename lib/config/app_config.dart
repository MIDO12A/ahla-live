class AppConfig {
  static const String appName = 'Ahla Live';
  static const String databaseUrl =
      'https://ahla-live-default-rtdb.firebaseio.com/';
  static const int zegoAppId = 2088500186;
  // Zego AppSign is a build-time secret — never hardcode it. Inject via:
  //   flutter build apk --dart-define=ZEGO_APP_SIGN=<appsign>
  // Falls back to an empty string so a missing define fails loudly (init guard)
  // instead of silently leaking a real signing key into the public repo.
  static const String zegoAppSign = String.fromEnvironment('ZEGO_APP_SIGN');
}
