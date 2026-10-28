# Mobile RDP (Android/iOS) - Arquitectura

Estructura añadida siguiendo las recomendaciones:
- native/bridge (engine_bridge.c/h) - puente C compartido
- android/app/src/main/cpp (JNI + CMake) - pegamento Android
- ios/Runner/RDP - pegamento iOS preparado
- lib/mobile_rdp (engine/domain/data/presentation) - UI + lógica aislada
- Usa Texture + FFI + flutter_secure_storage + drift preparado

Estado: Esqueleto PoC. Integrar FreeRDP 3.x como submodule en native/freerdp/ para habilitar render real.
