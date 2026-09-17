import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/modelos.dart';
import 'package:onix_referidos/src/datos/repositorio_referidos.dart';
import 'package:onix_referidos/src/nucleo/arranque.dart';
import 'package:onix_referidos/src/nucleo/entorno.dart';
import 'package:onix_referidos/src/utiles/telefono.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_como_funciona.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_cta_final.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_hero.dart';
import 'package:onix_referidos/src/ui/secciones/pie_pagina.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_onix_drive.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_premios.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_reclamo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repositorio que devuelve lo mismo que un proyecto Supabase recién creado:
/// cero participantes y ninguna sesión abierta.
///
/// El repositorio en memoria siembra datos de ejemplo, así que hasta ahora
/// la landing nunca se había probado con la campaña realmente vacía, que es
/// justo el estado en el que la ve la primera persona que entra.
class _RepositorioVacio implements RepositorioReferidos {
  @override
  Future<Participante?> sesionActual() async => null;

  @override
  Future<void> cerrarSesion() async {}

  @override
  Future<InvitacionEmitida> generarInvitacion(String idParticipante) async =>
      throw UnimplementedError();

  @override
  Future<EnlaceInvitacion> miEnlace(String idParticipante) async =>
      throw UnimplementedError();

  @override
  Future<List<InvitacionEmitida>> misInvitaciones(
    String idParticipante,
  ) async => const [];

  @override
  Future<DesafioVerificacion> iniciarRegistro({
    required String nombre,
    required String contrasena,
    required String telefono,
    required PaisTelefono pais,
  }) async => throw UnimplementedError();

  @override
  Future<CodigoAsignado> obtenerCodigoDeEnlace(String tokenEnlace) async =>
      throw UnimplementedError();

  @override
  Future<ResultadoCanje> validarCodigo({
    required String codigoInvitacion,
    required String telefono,
    required PaisTelefono pais,
  }) async => throw UnimplementedError();

  @override
  Future<Participante> iniciarSesion({
    required String telefono,
    required PaisTelefono pais,
    required String contrasena,
  }) async => throw UnimplementedError();

  @override
  Future<DesafioVerificacion> reenviarCodigo(String idDesafio) async =>
      throw UnimplementedError();

  @override
  Future<Participante> confirmarVerificacion({
    required String idDesafio,
    required String codigo,
  }) async => throw UnimplementedError();

  @override
  Future<List<EventoReferido>> misReferidos(String idParticipante) async =>
      const [];

  @override
  Future<Participante> refrescarParticipante(String idParticipante) async =>
      throw UnimplementedError();

  @override
  Future<ReclamoPremio?> miReclamo(String idParticipante) async => null;

  @override
  Future<ReclamoPremio> reclamarPremio(String idParticipante) async =>
      throw UnimplementedError();

  @override
  Future<ReclamoPremio> abrirCaja({
    required String idParticipante,
    required String idReclamo,
    required int caja,
  }) async => throw UnimplementedError();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> montar(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AplicacionOnix(
        arranque: ResultadoArranque(
          repositorio: _RepositorioVacio(),
          origen: OrigenDatos.supabase,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SingleChildScrollView paginaVisible(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).last);

  testWidgets('el inicio solo muestra el hero y el pie', (tester) async {
    await montar(tester, const Size(1440, 1600));

    expect(find.byType(SeccionHero), findsOneWidget);
    expect(find.byType(PiePagina), findsOneWidget);
    for (final tipo in [
      SeccionComoFunciona,
      SeccionPremios,
      SeccionReclamo,
      SeccionOnixDrive,
      SeccionCtaFinal,
    ]) {
      expect(find.byType(tipo), findsNothing, reason: '$tipo no va al inicio');
    }
    // Ya no existen el ranking, el juego limpio ni las preguntas.
    expect(find.text('Quiénes van adelante'), findsNothing);
    expect(find.text('Preguntas'), findsNothing);
  });

  testWidgets('cada enlace de la barra abre su propia pantalla', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 1600));

    final destinos = <String, List<Type>>{
      'Cómo funciona': [SeccionComoFunciona, SeccionCtaFinal],
      'Premios': [SeccionPremios, SeccionReclamo, SeccionCtaFinal],
      'Onix Drive': [SeccionOnixDrive, SeccionCtaFinal],
    };
    for (final MapEntry(key: enlace, value: tipos) in destinos.entries) {
      await tester.tap(find.text(enlace).last);
      await tester.pumpAndSettle();
      for (final tipo in tipos) {
        expect(find.byType(tipo), findsOneWidget, reason: '$enlace: $tipo');
        final alto = tester.getSize(find.byType(tipo)).height;
        expect(alto, greaterThan(100), reason: '$enlace: $tipo quedó con $alto');
      }
      expect(find.byType(SeccionHero), findsNothing);
    }

    // «Participar» vuelve al inicio, con el formulario.
    await tester.tap(find.text('Participar'));
    await tester.pumpAndSettle();
    expect(find.byType(SeccionHero), findsOneWidget);
    expect(find.byType(SeccionPremios), findsNothing);
  });

  testWidgets('el botón del llamado final vuelve al inicio', (tester) async {
    await montar(tester, const Size(1440, 1600));
    await tester.tap(find.text('Premios').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Quiero participar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiero participar'));
    await tester.pumpAndSettle();

    expect(find.byType(SeccionHero), findsOneWidget);
  });

  testWidgets('las pantallas se pueden desplazar hacia abajo', (tester) async {
    await montar(tester, const Size(1440, 900));

    for (final enlace in ['Premios', 'Cómo funciona', 'Onix Drive']) {
      await tester.tap(find.text(enlace).last);
      await tester.pumpAndSettle();
      final desplazador = paginaVisible(tester).controller!;
      expect(desplazador.offset, 0, reason: '$enlace arranca arriba');

      // Se arrastra desde el cuerpo de la pagina, por debajo de la barra.
      await tester.dragFrom(const Offset(720, 600), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(desplazador.offset, greaterThan(0), reason: '$enlace se desplaza');
    }
  });

  testWidgets('la zona visible ocupa toda la ventana, no solo el encabezado', (
    tester,
  ) async {
    // Regresion: `Scaffold` da al body restricciones de alto sueltas y un
    // `Stack` suelto se encoge hasta su hijo no posicionado mas grande, que
    // es la barra de navegacion. Cuando eso pasa, la pagina entera queda
    // comprimida en una franja de 88 px y solo se ve el encabezado.
    const alto = 900.0;
    await montar(tester, const Size(1440, alto));
    await tester.tap(find.text('Premios').last);
    await tester.pumpAndSettle();

    final desplazador = paginaVisible(tester).controller!;
    expect(desplazador.position.viewportDimension, alto);
    expect(
      desplazador.position.maxScrollExtent,
      greaterThan(alto),
      reason: 'tiene que haber contenido por debajo del pliegue',
    );
  });

  testWidgets('en computador se ve la barra de desplazamiento', (tester) async {
    // Flutter prueba como si fuera Android: aqui se simula un computador.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await montar(tester, const Size(1440, 900));
    await tester.tap(find.text('Premios').last);
    await tester.pumpAndSettle();

    final barras = tester.widgetList<Scrollbar>(find.byType(Scrollbar));
    expect(barras.any((barra) => barra.thumbVisibility == true), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('en celular la barra solo aparece al deslizar', (tester) async {
    await montar(tester, const Size(390, 844));
    final barra = tester.widget<Scrollbar>(
      find.byKey(const Key('barra-desplazamiento')),
    );
    expect(barra.thumbVisibility, isFalse);
  });
}
