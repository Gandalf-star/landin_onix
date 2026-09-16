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
import 'package:onix_referidos/src/ui/secciones/seccion_juego_limpio.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_onix_drive.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_preguntas.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_premios.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_ranking.dart';
import 'package:onix_referidos/src/ui/secciones/seccion_reclamo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repositorio que devuelve lo mismo que un proyecto Supabase recién creado:
/// cero participantes, ranking vacío y ninguna sesión abierta.
///
/// El repositorio en memoria siembra datos de ejemplo, así que hasta ahora
/// la landing nunca se había probado con la campaña realmente vacía, que es
/// justo el estado en el que la ve la primera persona que entra.
class _RepositorioVacio implements RepositorioReferidos {
  @override
  Future<List<FilaRanking>> obtenerRanking({
    int limite = 10,
    String? idParticipante,
  }) async => const [];

  @override
  Future<Participante?> sesionActual() async => null;

  @override
  Future<void> cerrarSesion() async {}

  @override
  Future<InvitacionEmitida> generarInvitacion(String idParticipante) async =>
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
    String? codigoInvitador,
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

  testWidgets('con la campaña vacía se montan todas las secciones', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 2400));

    // Cada sección de la página debe existir en el árbol aunque no haya
    // ningún participante todavía.
    expect(find.byType(SeccionHero), findsOneWidget, reason: 'hero');
    expect(find.byType(SeccionComoFunciona), findsOneWidget, reason: 'cómo');
    expect(find.byType(SeccionPremios), findsOneWidget, reason: 'premios');
    expect(find.byType(SeccionReclamo), findsOneWidget, reason: 'reclamo');
    expect(find.byType(SeccionRanking), findsOneWidget, reason: 'ranking');
    expect(find.byType(SeccionJuegoLimpio), findsOneWidget, reason: 'juego');
    expect(find.byType(SeccionOnixDrive), findsOneWidget, reason: 'onix');
    expect(find.byType(SeccionPreguntas), findsOneWidget, reason: 'preguntas');
    expect(find.byType(SeccionCtaFinal), findsOneWidget, reason: 'cta');
  });

  testWidgets('las secciones ocupan alto real, no quedan colapsadas', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 2400));

    for (final entrada in <String, Type>{
      'hero': SeccionHero,
      'cómo funciona': SeccionComoFunciona,
      'premios': SeccionPremios,
      'ranking': SeccionRanking,
      'preguntas': SeccionPreguntas,
    }.entries) {
      final alto = tester.getSize(find.byType(entrada.value)).height;
      expect(
        alto,
        greaterThan(100),
        reason: 'la sección ${entrada.key} quedó con alto $alto',
      );
    }
  });

  testWidgets('los enlaces del encabezado desplazan la pagina', (tester) async {
    // Alto de ventana real de navegador: el hero ocupa toda la pantalla y
    // hay que desplazarse para ver el resto. Es el escenario en el que la
    // persona dice "solo veo el encabezado".
    await montar(tester, const Size(1440, 900));

    final desplazador = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    expect(desplazador.offset, 0, reason: 'arranca arriba del todo');

    await tester.tap(find.text('Premios').first);
    await tester.pumpAndSettle();

    expect(
      desplazador.offset,
      greaterThan(0),
      reason: 'tocar "Premios" en el encabezado tiene que desplazar',
    );
  });

  testWidgets('la pagina se puede desplazar con la rueda del raton', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));

    final desplazador = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;

    // Se arrastra desde un punto del cuerpo de la pagina, por debajo de la
    // barra de navegacion: si se toma el centro del widget, el puntero cae
    // sobre la barra y es ella la que recibe el gesto.
    await tester.dragFrom(const Offset(720, 600), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(
      desplazador.offset,
      greaterThan(0),
      reason: 'la pagina tiene que desplazarse al arrastrar',
    );
  });

  testWidgets('la zona visible ocupa toda la ventana, no solo el encabezado', (
    tester,
  ) async {
    // Regresion: `Scaffold` da al body restricciones de alto sueltas y un
    // `Stack` suelto se encoge hasta su hijo no posicionado mas grande, que
    // es la barra de navegacion. Cuando eso pasa, la landing entera queda
    // comprimida en una franja de 88 px y solo se ve el encabezado.
    const alto = 900.0;
    await montar(tester, const Size(1440, alto));

    final desplazador = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;

    expect(
      desplazador.position.viewportDimension,
      alto,
      reason: 'la pagina debe ocupar el alto completo de la ventana',
    );
    expect(
      desplazador.position.maxScrollExtent,
      greaterThan(alto),
      reason: 'y tiene que haber contenido por debajo del pliegue',
    );
  });
}
