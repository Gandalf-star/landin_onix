import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/nucleo/arranque.dart';

Future<void> main() async {
  // Necesario porque el arranque lee el .env y abre la conexion con Supabase
  // antes de dibujar la primera pantalla.
  WidgetsFlutterBinding.ensureInitialized();
  final arranque = await arrancar();
  runApp(AplicacionOnix(arranque: arranque));
}
