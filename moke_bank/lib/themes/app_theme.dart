import 'package:flutter/material.dart';

import 'app_colors.dart';

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: naranja,
    onPrimary: fondo,
    secondary: naranja,
    onSecondary: fondo,
    secondaryContainer: fondoNaranjaSuave,
    onSecondaryContainer: naranja,
    surface: tarjetas,
    onSurface: textoPrincipal,
    onSurfaceVariant: textoSecundario50,
    outline: borde10,
    error: textoError,
  );
  final base = ThemeData(colorScheme: scheme);
  const radius = BorderRadius.all(Radius.circular(14));
  const border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: borde10),
  );
  return base.copyWith(
    scaffoldBackgroundColor: fondo,
    dividerColor: borde06,
    appBarTheme: const AppBarTheme(
      backgroundColor: fondo,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textoPrincipal,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -.65,
      ),
      headlineLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.04,
      ),
    ),
    cardTheme: const CardThemeData(
      color: tarjetas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borde06),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: tarjetas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tarjetas,
      hoverColor: borde06,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: naranja),
      ),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: error)),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: borde10),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 62,
      backgroundColor: const Color(0xFF121215),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? naranja
              : textoSecundario50,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? naranja
              : textoSecundario50,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: tarjetas,
      indicatorColor: fondoNaranjaSuave,
      selectedIconTheme: IconThemeData(color: naranja),
      unselectedIconTheme: IconThemeData(color: textoSecundario50),
      selectedLabelTextStyle: TextStyle(color: naranja),
      unselectedLabelTextStyle: TextStyle(color: textoSecundario50),
    ),
  );
}
