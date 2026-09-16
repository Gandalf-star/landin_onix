import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/app.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/nucleo/arranque.dart';
import 'package:onix_referidos/src/nucleo/entorno.dart';
import 'package:onix_referidos/src/ui/pagina_landing.dart';
import 'package:onix_referidos/src/ui/premio/dialogo_cajas.dart';
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

  /// Estira la vista al alto de toda la pagina, asi se construyen y se
  /// revisan todas las secciones y no solo la primera pantalla.
  Future<void> mostrarPaginaCompleta(WidgetTester tester, Size tamano) async {
    final pagina = find
        .descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Column),
        )
        .first;
    tester.view.physicalSize = Size(tamano.width, tester.getSize(pagina).height);
    await tester.pumpAndSettle();
  }

  for (final MapEntry(key: nombre, value: tamano) in tamanos.entries) {
    group('$nombre (${tamano.width.toInt()}x${tamano.height.toInt()})', () {
      testWidgets('la landing completa no se desborda', (tester) async {
        await montar(tester, tamano);
        await mostrarPaginaCompleta(tester, tamano);
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
