import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'dispositivo.dart';

/// Lee los rasgos del navegador. Todo va protegido: un navegador que
/// bloquee alguna API no puede dejar a la persona sin poder registrarse.
Future<InfoDispositivo> leerInfoDispositivo() async {
  final navegador = web.window.navigator;
  final agente = _seguro(() => navegador.userAgent);

  // Rasgos que entran en la firma: estables entre visitas del mismo
  // navegador y distintos entre dispositivos diferentes.
  final paraFirma = <String, String>{
    'agente': agente,
    'plataforma': _seguro(() => navegador.platform),
    'idiomas': _seguro(
      () => navegador.languages.toDart.map((i) => i.toDart).join(','),
    ),
    'nucleos': _seguro(() => '${navegador.hardwareConcurrency}'),
    'tactil': _seguro(() => '${navegador.maxTouchPoints}'),
    'pantalla': _seguro(() {
      final pantalla = web.window.screen;
      return '${pantalla.width}x${pantalla.height}'
          '@${web.window.devicePixelRatio}';
    }),
    'color': _seguro(() => '${web.window.screen.colorDepth}'),
    'zona_horaria': _zonaHoraria(),
    'lienzo': _huellaLienzo(),
  };

  final firma = UtilesDispositivo.firmaDe(paraFirma);

  // Lo que se guarda para que el administrador lo lea (sin el lienzo, que
  // es un texto enorme y no le dice nada a una persona).
  final rasgos = <String, String>{
    'descripcion': UtilesDispositivo.describir(agente),
    'agente': agente,
    'plataforma': paraFirma['plataforma']!,
    'idioma': _seguro(() => navegador.language),
    'pantalla': paraFirma['pantalla']!,
    'zona_horaria': paraFirma['zona_horaria']!,
    'nucleos': paraFirma['nucleos']!,
    'tactil': paraFirma['tactil']!,
  };

  return InfoDispositivo(firma: firma, rasgos: rasgos);
}

String _seguro(String Function() lectura) {
  try {
    return lectura();
  } catch (_) {
    return '';
  }
}

String _zonaHoraria() {
  try {
    return _FormatoFecha().resolvedOptions().timeZone;
  } catch (_) {
    return 'UTC${DateTime.now().timeZoneOffset.inMinutes}';
  }
}

/// El mismo dibujo sale con diferencias minimas segun la GPU, el sistema y
/// las fuentes instaladas: es uno de los rasgos que mejor separa equipos.
String _huellaLienzo() {
  try {
    final lienzo = web.HTMLCanvasElement()
      ..width = 240
      ..height = 60;
    final contexto = lienzo.context2D
      ..textBaseline = 'top'
      ..font = '16px Arial'
      ..fillStyle = '#f60'.toJS;
    contexto.fillRect(110, 1, 62, 20);
    contexto
      ..fillStyle = '#069'.toJS
      ..fillText('Onix Drive · Reto 50 ñ 🚕', 2, 15);
    contexto
      ..fillStyle = 'rgba(102, 204, 0, 0.7)'.toJS
      ..fillText('Onix Drive · Reto 50 ñ 🚕', 4, 17);
    return UtilesDispositivo.firmaDe({'lienzo': lienzo.toDataURL()});
  } catch (_) {
    return '';
  }
}

@JS('Intl.DateTimeFormat')
extension type _FormatoFecha._(JSObject _) implements JSObject {
  external _FormatoFecha();
  external _OpcionesFecha resolvedOptions();
}

extension type _OpcionesFecha._(JSObject _) implements JSObject {
  external String get timeZone;
}
