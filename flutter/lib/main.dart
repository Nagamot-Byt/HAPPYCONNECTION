import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/home_page.dart';
import 'providers/connection_provider.dart';

void main() {
  runApp(const HappyConnectionApp());
}

class HappyConnectionApp extends StatelessWidget {
  const HappyConnectionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ],
      child: MaterialApp(
        title: 'HAPPYCONNECTION',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(
            primary: Colors.grey[800]!,
            secondary: Colors.grey[700]!,
            tertiary: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.grey[900],
            elevation: 0,
            centerTitle: true,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
