import 'package:flutter/material.dart';

/// Global navigator for push / notification deep-links before [MaterialApp] child context exists.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
