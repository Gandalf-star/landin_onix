import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/arranque.dart';
import 'package:onix_referidos/src/nucleo/entorno.dart';
import 'package:onix_referidos/src/ui/navegacion.dart';
import 'package:onix_referidos/src/ui/pagina_landing.dart';
import 'package:onix_referidos/src/ui/premio/dialogo_cajas.dart';
import 'package:onix_referidos/src/ui/secciones/barra_navegacion.dart';
import 'package:onix_referidos/src/utiles/telefono.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fuentes_prueba.dart';
import 'reglas_antifraude_test.dart' show registrar;

/// La landing se publica para celular, tablet y computador: en cada tamaño
/// tiene que montar sin desbordes (las franjas amarillas y negras de Flutter
/// hacen fallar la prueba) en sus estados principales.
void main() {
  setUpAll(cargarFuentesReales);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const tamanos = <String, Size>{
    'celular chico': Size(320, 568),
    'celular': Size(360, 800),
    'iPhone': Size(390, 844),
    'celular acostado': Size(844, 390),
    'tablet vertical': Size(768, 1024),
    'tablet horizontal': Size(1024, 768),
    'computador': Size(1440, 900),
  };

  Future<void> montar(
    WidgetTester tester,
    Size tamano, {
    Future<void> Function(RepositorioEnMemoria)? preparar,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repositorio = RepositorioEnMemoria();
    if (preparar != null) {
      await tester.runAsync(() => preparar(repositorio));
    }
    await tester.pumpWidget(
      AplicacionOnix(
        arranque: ResultadoArranque(
          repositorio: repositorio,
          origen: OrigenDatos.memoria,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ///Estira la vista al alto de toda la pagina, asi se construyen y se
  /// revisan todas las secciones y no solo la primera pantalla.
  Future<void> mostrarPaginaCompleta(WidgetTester tester, Size tamano) async {
    final pagina = find
        .descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Column),
        )
        .first;
    tester.view.physicalSize = Size(
      tamano.width,
      tester.getSize(pagina).height,
    );
    await tester.pumpAndSettle();
  }

  group('desplazamiento en computador', () {
    Future<ScrollPosition> posicionPagina(WidgetTester tester) async {
      final estado = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      return estado.position;
    }

    testWidgets('la rueda del mouse baja la página', (tester) async {
      await montar(tester, const Size(1440, 900));
      final posicion = await posicionPagina(tester);
      expect(posicion.pixels, 0);

      final raton = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(raton.hover(const Offset(720, 450)));
      await tester.sendEventToBinding(raton.scroll(const Offset(0, 400)));
      await tester.pumpAndSettle();

      expect(posicion.pixels, greaterThan(0));
    });

    for (final ancho in [1440.0, 600.0]) {
      testWidgets('la barra de desplazamiento queda fija con ventana de '
          '${ancho.toInt()} px', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await montar(tester, Size(ancho, 900));

        final barra = tester.widget<Scrollbar>(
          find.byKey(const Key('barra-desplazamiento')),
        );
        expect(barra.thumbVisibility, isTrue);
        expect(barra.trackVisibility, isTrue);
        // La barra se dibuja por encima de la barra de navegacion.
        expect(
          find.descendant(
            of: find.byKey(const Key('barra-desplazamiento')),
            matching: find.byType(BarraNavegacion),
          ),
          findsOneWidget,
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  for (final MapEntry(key: nombre, value: tamano) in tamanos.entries) {
    group('$nombre (${tamano.width.toInt()}x${tamano.height.toInt()})', () {
      for (final pagina in PaginaOnix.values) {
        testWidgets('la pantalla ${pagina.titulo} no se desborda', (
          tester,
        ) async {
          await montar(tester, tamano);
          NavegacionOnix.ir(tester.element(find.byType(PaginaLanding)), pagina);
          await tester.pumpAndSettle();
          await mostrarPaginaCompleta(tester, tamano);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('el menú de navegación cabe', (tester) async {
        await montar(tester, tamano);
        final menu = find.byTooltip('Menú');
        if (menu.evaluate().isEmpty) return;
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Onix Drive'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('el código de 6 dígitos cabe en la tarjeta', (tester) async {
        await montar(tester, tamano);
        final controlador = ProveedorCampana.accion(
          tester.element(find.byType(PaginaLanding)),
        );
        await tester.runAsync(
          () => controlador.registrar(
            nombre: 'Camila Torres',
            contrasena: 'Clave1234',
            telefono: '964831207',
            pais: PaisTelefono.chile,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirma tu número'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('el código que entrega el link cabe en la tarjeta', (
        tester,
      ) async {
        late String token;
        await montar(
          tester,
          tamano,
          preparar: (repositorio) async {
            repositorio.huellaDispositivo = 'celular_de_camila';
            final camila = await registrar(
              repositorio,
              nombre: 'María Fernanda González Contreras',
              telefono: '9 6483 1207',
            );
            token = (await repositorio.miEnlace(camila.id)).token;
            await repositorio.cerrarSesion();
            repositorio.huellaDispositivo = 'celular_de_matias';
          },
        );

        final controlador = ProveedorCampana.accion(
          tester.element(find.byType(PaginaLanding)),
        );
        controlador.tokenEnlaceDetectado = token;
        await tester.runAsync(controlador.reintentarCodigoAsignado);

        // Centrada, para que la barra de navegación fija no la tape.
        await Scrollable.ensureVisible(
          tester.element(find.text('Tengo un código')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tengo un código'));
        await tester.pumpAndSettle();
        await mostrarPaginaCompleta(tester, tamano);
        expect(find.text('Valida tu invitación'), findsOneWidget);
        expect(find.textContaining('María te invitó'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.runAsync(
          () => controlador.validarCodigo(
            codigoInvitacion: controlador.codigoAsignado!.codigo,
            telefono: '964831208',
            pais: PaisTelefono.chile,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('¡Invitación validada!'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('el link y el código individual no se desbordan', (
        tester,
      ) async {
        await montar(
          tester,
          tamano,
          preparar: (repositorio) => registrar(
            repositorio,
            nombre: 'Camila Torres',
            telefono: '9 6483 1207',
          ),
        );
        final controlador = ProveedorCampana.accion(
          tester.element(find.byType(PaginaLanding)),
        );
        await tester.runAsync(controlador.generarInvitacion);
        await tester.pumpAndSettle();
        await mostrarPaginaCompleta(tester, tamano);

        expect(find.text('Compartir link por WhatsApp'), findsOneWidget);
        expect(find.text('CÓDIGO PARA TU PRÓXIMO INVITADO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('el panel con premio no se desborda', (tester) async {
        await montar(
          tester,
          tamano,
          preparar: (repositorio) async {
            final participante = await registrar(
              repositorio,
              nombre: 'María Fernanda González Contreras',
              telefono: '9 6483 1207',
            );
            await repositorio.simularInvitados(participante.id, 50);
          },
        );
        final controlador = ProveedorCampana.accion(
          tester.element(find.byType(PaginaLanding)),
        );
        await tester.runAsync(() async {
          await controlador.reclamarPremio();
          await controlador.abrirCaja(1);
        });
        await tester.pumpAndSettle();
        await mostrarPaginaCompleta(tester, tamano);

        expect(find.text('Tu premio'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('la escena de las cajas no se desborda', (tester) async {
        await montar(
          tester,
          tamano,
          preparar: (repositorio) async {
            final participante = await registrar(
              repositorio,
              nombre: 'Camila Torres',
              telefono: '9 6483 1207',
            );
            await repositorio.simularInvitados(participante.id, 50);
          },
        );
        final contexto = tester.element(find.byType(PaginaLanding));
        final controlador = ProveedorCampana.accion(contexto);
        await tester.runAsync(() async {
          await controlador.reclamarPremio();
          await controlador.abrirCaja(0);
        });
        await tester.pumpAndSettle();

        // Con la caja ya abierta la escena arranca en el ticket, con los
        // botones finales a la vista. Sus animaciones se repiten, por eso
        // se avanza el reloj a mano en vez de esperar a que se detengan.
        DialogoCajas.mostrar(contexto);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(find.text('Copiar código'), findsOneWidget);
        expect(find.text('Listo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
