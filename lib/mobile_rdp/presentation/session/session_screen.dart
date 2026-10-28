import 'package:flutter/material.dart';
import 'remote_canvas.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: RemoteCanvas(textureId: null)),
    );
  }
}
