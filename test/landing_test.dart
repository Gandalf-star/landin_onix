import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/controlador_referidos.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/arranque.dart';
import 'package:onix_referidos/src/nucleo/entorno.dart';
import 'package:onix_referidos/src/nucleo/tema_onix.dart';
import 'package:onix_referidos/src/ui/registro/tarjeta_participacion.dart';
import 'package:onix_referidos/src/utiles/telefono.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pruebas de humo: comprueban que la landing monta completa y que el
/// formulario de participación reacciona, sin depender de ningún backend.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> montarLanding(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Las pruebas siempre corren contra el repositorio en memoria: la
    // landing no debe depender de que haya un backend levantado.
    await tester.pumpWidget(
      AplicacionOnix(
        arranque: ResultadoArranque(
          repositorio: RepositorioEnMemoria(),
          origen: OrigenDatos.memoria,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Monta sólo la tarjeta de participación, para probar el formulario sin
  /// el resto de la página encima.
  Future<void> montarFormulario(WidgetTester tester) async {
    tester.view.physicalSize = const Size(560, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Ojo: no se hace `await` de inicializar(). Dentro de un widget test el
    // reloj es simulado y los Future.delayed del repositorio sólo avanzan
    // cuando el tester bombea frames, así que esperar aquí colgaría la prueba.
    final controlador = ControladorReferidos(RepositorioEnMemoria());
    unawaited(controlador.inicializar());
    addTearDown(controlador.dispose);

    await tester.pumpWidget(
      ProveedorCampana(
        controlador: controlador,
        child: MaterialApp(
          theme: construirTemaOnix(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: TarjetaParticipacion(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Llena los datos de la cuenta del formulario de registro.
  Future<void> llenarCuenta(
    WidgetTester tester, {
    String nombre = 'Camila Torres',
  }) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre y apellido'),
      nombre,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mínimo 8, con letras y números'),
      'Clave1234',
    );
  }

  /// Toca un widget asegurandose antes de que este dentro de la pantalla.
  Future<void> tocar(WidgetTester tester, Finder objetivo) async {
    await tester.ensureVisible(objetivo);
    await tester.pumpAndSettle();
    await tester.tap(objetivo);
    await tester.pumpAndSettle();
  }

  testWidgets('monta la landing completa en escritorio', (tester) async {
    await montarLanding(tester, const Size(1440, 1400));

    expect(
      find.textContaining('Abre tu caja premiada', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Participa gratis'), findsOneWidget);
    expect(find.text('Quiénes van adelante'), findsOneWidget);
    expect(find.text('Tres cajas cerradas. Una es tuya.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el hero ya no muestra contadores públicos', (tester) async {
    await montarLanding(tester, const Size(1440, 1400));

    expect(find.text('personas participando'), findsNothing);
    expect(find.text('invitaciones válidas'), findsNothing);
    expect(find.text('intentos de trampa bloqueados'), findsNothing);
    // En su lugar se muestran los premios que pueden salir de las cajas.
    expect(find.text('EN LAS CAJAS TE PUEDE TOCAR'), findsOneWidget);
  });

  testWidgets('monta la landing completa en móvil', (tester) async {
    await montarLanding(tester, const Size(390, 844));

    expect(find.text('Participa gratis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rechaza un celular con formato inválido', (tester) async {
    await montarFormulario(tester);

    await llenarCuenta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, '9 1234 5678'),
      '2234',
    );
    await tocar(tester, find.text('Crear mi cuenta'));

    expect(find.textContaining('9 dígitos que empiezan con 9'), findsOneWidget);
  });

  testWidgets('exige aceptar las bases antes de continuar', (tester) async {
    await montarFormulario(tester);

    await llenarCuenta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, '9 1234 5678'),
      '964831207',
    );
    await tocar(tester, find.text('Crear mi cuenta'));

    expect(
      find.text('Debes aceptar las bases para participar.'),
      findsOneWidget,
    );
  });

  testWidgets('con los datos correctos pasa a la verificación', (tester) async {
    await montarFormulario(tester);

    await llenarCuenta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, '9 1234 5678'),
      '964831207',
    );
    await tocar(tester, find.byType(Checkbox));
    await tocar(tester, find.text('Crear mi cuenta'));

    expect(find.text('Confirma tu número'), findsOneWidget);
    expect(find.textContaining('+56 9 6483 1207'), findsOneWidget);
    expect(find.textContaining('Modo demostración'), findsOneWidget);
  });

  testWidgets('permite registrarse con un celular venezolano', (tester) async {
    await montarFormulario(tester);

    // Por defecto el selector queda en Chile: hay que cambiarlo a Venezuela.
    await tocar(tester, find.byType(DropdownButton<PaisTelefono>));
    await tester.tap(find.text('+58').last);
    await tester.pumpAndSettle();

    await llenarCuenta(tester, nombre: 'Luis Pérez');
    await tester.enterText(
      find.widgetWithText(TextFormField, PaisTelefono.venezuela.ejemplo),
      '4129034567',
    );
    await tocar(tester, find.byType(Checkbox));
    await tocar(tester, find.text('Crear mi cuenta'));

    expect(find.text('Confirma tu número'), findsOneWidget);
    expect(find.textContaining('+58 412 903 4567'), findsOneWidget);
    expect(find.textContaining('Modo demostración'), findsOneWidget);
  });

  testWidgets('con una contraseña débil no avanza', (tester) async {
    await montarFormulario(tester);

    await llenarCuenta(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mínimo 8, con letras y números'),
      'corta1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '9 1234 5678'),
      '964831207',
    );
    await tocar(tester, find.byType(Checkbox));
    await tocar(tester, find.text('Crear mi cuenta'));

    expect(find.text('Usa al menos 8 caracteres'), findsOneWidget);
    expect(find.text('Confirma tu número'), findsNothing);
  });

  testWidgets('el registro ya no pide usuario ni repetir la contraseña', (
    tester,
  ) async {
    await montarFormulario(tester);

    expect(find.text('Nombre de usuario'), findsNothing);
    expect(find.text('Repite tu contraseña'), findsNothing);
    expect(find.text('Tu nombre'), findsOneWidget);
    expect(find.text('Tu celular'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);

    // Deja que termine la carga inicial del repositorio en memoria: si no,
    // el test acaba con temporizadores pendientes.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('el ingreso pide celular y contraseña, no el nombre', (
    tester,
  ) async {
    await montarFormulario(tester);

    await tocar(tester, find.text('Ya tengo cuenta · Ingresar'));

    expect(find.text('Ingresa a tu cuenta'), findsOneWidget);
    expect(find.text('Tu celular'), findsOneWidget);
    expect(find.text('Nombre y apellido'), findsNothing);
    expect(find.text('Nombre de usuario'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, '9 1234 5678'),
      '964831207',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tu contraseña'),
      'Clave1234',
    );
    await tocar(tester, find.text('Ingresar'));

    expect(find.text('Celular o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('Confirma tu número'), findsNothing);
  });
}
