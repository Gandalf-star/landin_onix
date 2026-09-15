import 'dart:io';

import 'package:flutter/services.dart';

/// Carga fuentes reales en las pruebas de diseño.
///
/// Por defecto `flutter test` dibuja cada letra como un cuadrado tan ancho
/// como alto: un titulo mide casi el doble que en el navegador y aparecen
/// desbordes que en la web no existen. Aqui se registra Roboto (la que usa
/// Flutter Web cuando no hay otra) bajo los nombres que pide el tema, junto
/// con los iconos de Material, tomadas del propio SDK de Flutter.
Future<void> cargarFuentesReales() async {
  final raiz = Platform.environment['FLUTTER_ROOT'];
  if (raiz == null) return;
  final carpeta = '$raiz/bin/cache/artifacts/material_fonts';
  if (!Directory(carpeta).existsSync()) return;

  Future<ByteData> leer(String archivo) async =>
      ByteData.sublistView(File('$carpeta/$archivo').readAsBytesSync());

  for (final familia in ['Inter', 'Manrope', 'Roboto', 'Segoe UI']) {
    final cargador = FontLoader(familia);
    for (final archivo in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]) {
      cargador.addFont(leer(archivo));
    }
    await cargador.load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(leer('materialicons-regular.otf')))
      .load();
}
