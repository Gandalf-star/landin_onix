import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/controlador_referidos.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/tema_onix.dart';
import 'package:onix_referidos/src/ui/panel/panel_participante.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reglas_antifraude_test.dart' show registrar;

/// Pruebas del panel: generar codigos de invitacion de un solo uso y
/// mostrarlos listos para compartir por WhatsApp.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ControladorReferidos> montarPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repositorio = RepositorioEnMemoria();
    final controlador = ControladorReferidos(repositorio);
    addTearDown(controlador.dispose);

    // Fuera de `runAsync`, los `Future.delayed` del repositorio quedan
    // colgados: nada hace avanzar el reloj falso de los widget tests antes
    // de que exista un arbol montado sobre el que hacer `pump`. Se resuelve
    // aqui, de una vez, el registro y la carga inicial del panel.
    await tester.runAsync(() async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
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

  testWidgets('sin códigos generados invita a crear el primero', (
    tester,
  ) async {
    await montarPanel(tester);

    expect(
      find.textContaining('Genera un código para invitar'),
      findsOneWidget,
    );
    expect(find.text('Compartir por WhatsApp'), findsNothing);
  });

  testWidgets('generar un código lo muestra listo para compartir', (
    tester,
  ) async {
    await montarPanel(tester);

    await tester.tap(find.text('Generar código para invitar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('CÓDIGO PARA TU PRÓXIMO INVITADO'),
      findsOneWidget,
    );
    expect(find.text('Compartir por WhatsApp'), findsOneWidget);
    expect(find.text('Copiar mensaje de invitación'), findsOneWidget);
    expect(
      find.textContaining('Tus códigos de invitación (1)'),
      findsOneWidget,
    );
  });

  testWidgets('cada código generado es distinto y queda en la lista', (
    tester,
  ) async {
    final controlador = await montarPanel(tester);

    await tester.tap(find.text('Generar código para invitar'));
    await tester.pumpAndSettle();
    final primerCodigo = controlador.misInvitaciones.single.codigo;

    await tester.tap(find.text('Generar código para invitar'));
    await tester.pumpAndSettle();

    expect(controlador.misInvitaciones.length, 2);
    expect(controlador.misInvitaciones.first.codigo, isNot(primerCodigo));
    expect(
      find.textContaining('Tus códigos de invitación (2)'),
      findsOneWidget,
    );
  });
}
