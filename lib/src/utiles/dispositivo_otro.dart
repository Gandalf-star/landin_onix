import 'dart:io' show Platform;

import 'dispositivo.dart';

/// Fuera del navegador (pruebas en la VM): rasgos minimos y deterministas.
Future<InfoDispositivo> leerInfoDispositivo() async {
  final rasgos = <String, String>{
    'plataforma': Platform.operatingSystem,
    'idioma': Platform.localeName,
    'descripcion': 'Pruebas · ${Platform.operatingSystem}',
  };
  return InfoDispositivo(
    firma: UtilesDispositivo.firmaDe(rasgos),
    rasgos: rasgos,
  );
}
