import 'package:flutter/material.dart';

class RemoteCanvas extends StatelessWidget {
  final int? textureId;
  const RemoteCanvas({super.key, this.textureId});

  @override
  Widget build(BuildContext context) {
    if (textureId == null || textureId! < 0) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child: Text('Iniciando sesión RDP...',
                style: TextStyle(color: Colors.white))),
      );
    }
    return Texture(textureId: textureId!);
  }
}
