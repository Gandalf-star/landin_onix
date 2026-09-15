import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/controlador_referidos.dart';
import 'package:onix_referidos/src/datos/modelos.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/config_campana.dart';
import 'package:onix_referidos/src/nucleo/tema_onix.dart';
import 'package:onix_referidos/src/ui/panel/panel_participante.dart';
import 'package:onix_referidos/src/ui/premio/dialogo_cajas.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reglas_antifraude_test.dart' show registrar;

/// Recorrido del premio en pantalla: el botón «Reclamar premio», las tres
/// cajas y el ticket ganador con su código de confirmación.
///
/// La escena de las cajas tiene animaciones que se repiten (las cajas
/// flotan, los destellos giran), así que aquí se avanza el reloj con
/// `pump(duración)` en lugar de `pumpAndSettle`.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ControladorReferidos> montarPanel(
    WidgetTester tester, {
    required int tickets,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repositorio = RepositorioEnMemoria();
    final controlador = ControladorReferidos(repositorio);
    addTearDown(controlador.dispose);

    await tester.runAsync(() async {
      final participante = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      await repositorio.simularInvitados(participante.id, tickets);
      await controlador.inicializar();
    });

    await tester.pumpWidget(
      ProveedorCampana(
        controlador: controlador,
        child: MaterialApp(
          theme: construirTemaOnix(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: PanelParticipante(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controlador;
  }

  /// Avanza el reloj en pasos cortos para que corran temporizadores y
  /// animaciones de la escena.
  Future<void> avanzar(WidgetTester tester, Duration total) async {
    const paso = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < total; t += paso) {
      await tester.pump(paso);
    }
  }

  testWidgets('sin la meta no aparece el botón para reclamar', (tester) async {
    await montarPanel(tester, tickets: ConfigCampana.metaTickets - 1);

    expect(find.text('Reclamar premio'), findsNothing);
    expect(find.text('49 de 50 tickets'), findsOneWidget);
  });

  testWidgets('con 50 tickets se reclama, se elige una caja y sale el ticket',
      (tester) async {
    final controlador = await montarPanel(
      tester,
      tickets: ConfigCampana.metaTickets,
    );

    expect(find.text('¡Llegaste a 50 tickets!'), findsOneWidget);
    await tester.ensureVisible(find.text('Reclamar premio'));
    await tester.tap(find.text('Reclamar premio'));
    await avanzar(tester, const Duration(seconds: 1));

    // Las tres cajas, cerradas y sin pistas de qué hay dentro.
    expect(find.byType(EscenaCajas), findsOneWidget);
    expect(find.text('Elige tu caja'), findsOneWidget);
    expect(find.text('Caja 1'), findsOneWidget);
    expect(find.text('Caja 2'), findsOneWidget);
    expect(find.text('Caja 3'), findsOneWidget);
    expect(controlador.reclamo?.distribucion, isEmpty);
    for (final premio in PremioCaja.values) {
      expect(find.text(premio.titulo), findsNothing);
    }

    await tester.tap(find.text('Caja 2'));
    await tester.pump();
    expect(find.text('Abriendo tu caja…'), findsOneWidget);

    await avanzar(tester, const Duration(seconds: 5));

    final reclamo = controlador.reclamo!;
    expect(reclamo.cajaElegida, 1);
    expect(find.text('¡Felicitaciones!'), findsOneWidget);
    expect(find.text('TICKET GANADOR'), findsWidgets);
    expect(find.text('TU CAJA'), findsOneWidget);
    expect(find.text('Aquí había'), findsNWidgets(2));
    expect(
      find.text(reclamo.codigoConfirmacionVisible!),
      findsWidgets,
    );

    // Se cierra la escena: el panel queda con el ticket a la vista.
    await tester.tap(find.text('Listo'));
    await avanzar(tester, const Duration(seconds: 1));
    expect(find.byType(EscenaCajas), findsNothing);
    expect(find.text('Tu premio'), findsOneWidget);
    expect(find.text('En verificación'), findsOneWidget);
  });

  testWidgets('volver a abrir la escena muestra el mismo ticket, sin elegir',
      (tester) async {
    final controlador = await montarPanel(
      tester,
      tickets: ConfigCampana.metaTickets,
    );

    await tester.runAsync(() async {
      await controlador.reclamarPremio();
      await controlador.abrirCaja(0);
    });
    await tester.pump();

    await tester.ensureVisible(find.text('Ver mi ticket y las cajas'));
    await tester.tap(find.text('Ver mi ticket y las cajas'));
    await avanzar(tester, const Duration(seconds: 1));

    expect(find.text('¡Felicitaciones!'), findsOneWidget);
    expect(find.text('Elige tu caja'), findsNothing);
    expect(find.text('TU CAJA'), findsOneWidget);

    await tester.tap(find.text('Listo'));
    await avanzar(tester, const Duration(seconds: 1));
  });
}
