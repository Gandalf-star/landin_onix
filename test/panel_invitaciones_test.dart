import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/controlador_referidos.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/tema_onix.dart';
import 'package:onix_referidos/src/ui/panel/panel_participante.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reglas_antifraude_test.dart' show registrar;

/// Pruebas del panel: el link para invitar a muchos contactos por WhatsApp
/// y los codigos individuales.
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

  testWidgets('el panel muestra el link para compartir con muchos contactos', (
    tester,
  ) async {
    final controlador = await montarPanel(tester);

    expect(find.text('INVITA A TUS CONTACTOS'), findsOneWidget);
    expect(find.text('Compartir link por WhatsApp'), findsOneWidget);
    expect(find.text('¿A quién vas a invitar?'), findsNothing);

    final enlace = controlador.enlace!;
    expect(find.textContaining('?inv=${enlace.token}'), findsOneWidget);
    expect(find.textContaining('0 de 50 códigos entregados'), findsOneWidget);

    // El mensaje lleva el link, no un código: WhatsApp manda el mismo texto
    // a todos los contactos elegidos.
    final mensaje = controlador.mensajeDelEnlace(
      controlador.participante!,
      enlace,
    );
    expect(mensaje, contains('?inv=${enlace.token}'));
    expect(mensaje, isNot(contains('ONX-')));
    expect(
      ControladorReferidos.enlaceWhatsApp(mensaje).toString(),
      startsWith('https://wa.me/?text='),
    );
  });

  testWidgets('generar un código individual lo muestra listo para enviar', (
    tester,
  ) async {
    await montarPanel(tester);
    expect(find.text('CÓDIGO PARA TU PRÓXIMO INVITADO'), findsNothing);

    await tester.tap(find.text('Generar código para invitar'));
    await tester.pumpAndSettle();

    expect(find.text('CÓDIGO PARA TU PRÓXIMO INVITADO'), findsOneWidget);
    expect(find.text('Enviar código'), findsOneWidget);
    expect(
      find.textContaining('Tus códigos de invitación (1)'),
      findsOneWidget,
    );
  });

  testWidgets('cada código individual es distinto y queda en la lista', (
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
