import 'package:flutter/material.dart';

/// The app's navigator, handed to `MaterialApp.navigatorKey` in main.dart.
///
/// Lives here rather than in main.dart so services can reach it without
/// importing the entry point — main.dart imports the services, so a service
/// importing main.dart back would make the graph circular. Anything that has
/// to put UI on screen from outside the widget tree goes through this.
final GlobalKey<NavigatorState> pixoraNavigatorKey =
    GlobalKey<NavigatorState>();
