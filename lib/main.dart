import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassThemeData, LiquidGlassWidgets;

import 'app_controller.dart';
import 'core/database.dart';
import 'home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  final controller = AppController(CrmDatabase());
  runApp(LiquidGlassWidgets.wrap(
    adaptiveQuality: true,
    brightnessResolver: Theme.maybeBrightnessOf,
    theme: const GlassThemeData.ios27(),
    child: ClCrmApp(controller: controller),
  ));
  await controller.initialize();
}

class ClCrmApp extends StatelessWidget {
  const ClCrmApp({super.key, required this.controller});
  final AppController controller;
  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff087ee8), brightness: brightness);
    return ThemeData(useMaterial3: true, colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xfff5f7fa) : const Color(0xff10151b),
      appBarTheme: AppBarTheme(backgroundColor: brightness == Brightness.light ? const Color(0xfff5f7fa) : const Color(0xff10151b)),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.only(bottom: 8)),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true, fillColor: scheme.surface));
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, _) => MaterialApp(
    title: 'ClCrm', debugShowCheckedModeBanner: false, theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark), themeMode: controller.themeMode,
    locale: const Locale('zh', 'CN'), supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => controller.systemFont ? child! : MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(controller.fontScale)), child: child!),
    home: !controller.ready ? Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: controller.startupError == null ? const CircularProgressIndicator() : Column(
        mainAxisSize: MainAxisSize.min, children: [Text(controller.startupError!), const SizedBox(height: 20),
          FilledButton(onPressed: controller.initialize, child: const Text('重试'))]))))
      : HomeShell(controller: controller),
  ));
}
