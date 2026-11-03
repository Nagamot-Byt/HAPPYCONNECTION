import 'package:flutter/material.dart';
import 'package:medlink_connect/core/app_theme.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:medlink_connect/core/theme_controller.dart';
import 'package:medlink_connect/features/ui/home_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// The root widget for MedLink Connect.
class MedLinkConnectApp extends StatelessWidget {
  const MedLinkConnectApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final themeController = getIt<ThemeController>();
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.mode,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', ''),
          Locale('en', ''),
        ],
        home: const HomeScreen(),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  runApp(const MedLinkConnectApp());
}
