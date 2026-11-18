import 'package:flutter/material.dart';

/// Global navigator key attached to `MaterialApp.navigatorKey`.
///
/// Needed by widgets that are mounted *above* the Navigator (inside
/// `MaterialApp.builder` — e.g. the global gift banners and the floating
/// minimized-room bubble). Those widgets have no Navigator ancestor, so they
/// resolve the root navigator through this key instead.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// A context that lives *inside* the root [Navigator] (the overlay is a
/// descendant of it), so `Navigator.of(...)`, `showDialog(...)` and
/// `Provider.of(...)` all work from it.
///
/// Use this when a banner/mini overlay needs to show a dialog or push a route.
BuildContext? rootNavigatorContext() =>
    rootNavigatorKey.currentState?.overlay?.context;
