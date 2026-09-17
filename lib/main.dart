import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app.dart';
import 'src/nucleo/arranque.dart';

Future<void> main() async {
  // Necesario porque el arranque lee el .env y abre la conexion con Supabase
  // antes de dibujar la primera pantalla.
  WidgetsFlutterBinding.ensureInitialized();
  // Cada pantalla tiene una direccion limpia (/premios, /onix-drive). En
  // Vercel todas las rutas sirven index.html (ver vercel.json).
  usePathUrlStrategy();
  final arranque = await arrancar();
  runApp(AplicacionOnix(arranque: arranque));
}
