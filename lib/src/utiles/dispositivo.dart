import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'dispositivo_otro.dart'
    if (dart.library.js_interop) 'dispositivo_web.dart' as plataforma;

/// Lo que la landing sabe del dispositivo desde el que se usa.
///
/// Sirve para anclar el dispositivo del invitado al codigo que canjea: un
/// mismo celular solo puede aceptar UNA invitacion en toda la campana. Hay
/// dos piezas:
///
/// - La huella, un identificador aleatorio guardado en el navegador (la
///   genera cada repositorio). Es la que bloquea en el servidor.
/// - La [firma], un hash de rasgos del navegador (pantalla, idioma, zona
///   horaria, motor grafico...). No bloquea por si sola, porque dos
///   celulares iguales pueden coincidir, pero delata a quien borra la
///   huella o usa modo incognito: el panel admin marca las coincidencias.
@immutable
class InfoDispositivo {
  const InfoDispositivo({required this.firma, required this.rasgos});

  final String firma;

  /// Rasgos legibles que se guardan junto al anclaje para que el
  /// administrador pueda revisarlos.
  final Map<String, String> rasgos;

  String get descripcion => rasgos['descripcion'] ?? 'Dispositivo desconocido';

  Map<String, String> aJson() => {...rasgos, 'firma': firma};
}

abstract final class UtilesDispositivo {
  static Future<InfoDispositivo>? _enCurso;

  /// Lee el dispositivo una sola vez por carga de la pagina.
  static Future<InfoDispositivo> leer() =>
      _enCurso ??= plataforma.leerInfoDispositivo();

  /// Hash estable de los rasgos: mismo navegador, misma firma.
  static String firmaDe(Map<String, String> rasgos) {
    final claves = rasgos.keys.toList()..sort();
    final texto = claves.map((c) => '$c=${rasgos[c]}').join('|');
    return sha256.convert(utf8.encode(texto)).toString().substring(0, 32);
  }

  /// `Chrome 128 · Android 14` a partir del user agent.
  static String describir(String agente) {
    final navegador = _primeraCoincidencia(agente, [
      (RegExp(r'SamsungBrowser/(\d+)'), 'Samsung Internet'),
      (RegExp(r'EdgA?/(\d+)'), 'Edge'),
      (RegExp(r'OPR/(\d+)'), 'Opera'),
      (RegExp(r'Firefox/(\d+)'), 'Firefox'),
      (RegExp(r'FxiOS/(\d+)'), 'Firefox'),
      (RegExp(r'CriOS/(\d+)'), 'Chrome'),
      (RegExp(r'Chrome/(\d+)'), 'Chrome'),
      (RegExp(r'Version/(\d+)[\d.]* .*Safari'), 'Safari'),
    ]);
    final sistema = _primeraCoincidencia(agente, [
      (RegExp(r'Android (\d+)'), 'Android'),
      (RegExp(r'iPhone OS (\d+)'), 'iPhone iOS'),
      (RegExp(r'iPad; CPU OS (\d+)'), 'iPad iOS'),
      (RegExp(r'Windows NT (\d+)'), 'Windows'),
      (RegExp(r'Mac OS X (\d+)'), 'macOS'),
      (RegExp(r'CrOS'), 'ChromeOS'),
      (RegExp(r'Linux'), 'Linux'),
    ]);
    final partes = [?navegador, ?sistema];
    return partes.isEmpty ? 'Navegador desconocido' : partes.join(' · ');
  }

  static String? _primeraCoincidencia(
    String texto,
    List<(RegExp, String)> patrones,
  ) {
    for (final (patron, nombre) in patrones) {
      final coincidencia = patron.firstMatch(texto);
      if (coincidencia == null) continue;
      final version =
          coincidencia.groupCount >= 1 ? coincidencia.group(1) : null;
      return version == null ? nombre : '$nombre $version';
    }
    return null;
  }
}
