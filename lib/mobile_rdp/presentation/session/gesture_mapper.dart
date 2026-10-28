import 'package:flutter/gestures.dart';

class GestureMapper {
  int lastX = 0;
  int lastY = 0;
  void onPanUpdate(DragUpdateDetails d) {
    lastX += d.delta.dx.toInt();
    lastY += d.delta.dy.toInt();
  }
}
