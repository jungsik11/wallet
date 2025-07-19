import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: Colors.grey[900],
  cardColor: Colors.grey[850],
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey[800],
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  tabBarTheme: TabBarThemeData(
    indicatorColor: Colors.deepPurpleAccent, // Use a distinct color for indicator
    labelColor: Colors.white,
    unselectedLabelColor: Colors.grey[400],
  ),
);
