import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../nucleo/arranque.dart';
import '../nucleo/tema_onix.dart';
import 'componentes/distintivo_origen_datos.dart';
import 'componentes/efectos.dart';
import 'componentes/logo_onix.dart';
import 'componentes/seccion_pagina.dart';
import 'navegacion.dart';
import 'secciones/barra_navegacion.dart';
import 'secciones/pie_pagina.dart';

/// Esqueleto comun de todas las pantallas: contenido desplazable con su
/// barra de desplazamiento, barra de navegacion fija arriba y pie de pagina.
class EstructuraPagina extends StatefulWidget {
  const EstructuraPagina({
    super.key,
    required this.pagina,
    required this.arranque,
    required this.secciones,
  });

  final PaginaOnix pagina;
  final ResultadoArranque arranque;
  final List<Widget> secciones;

  @override
  State<EstructuraPagina> createState() => _EstructuraPaginaState();
}

class _EstructuraPaginaState extends State<EstructuraPagina> {
  final _desplazador = ScrollController();

  @override
  void dispose() {
    _desplazador.dispose();
    super.dispose();
  }

  /// En computador la barra queda siempre a la vista, aunque la ventana del
  /// navegador sea angosta: con mouse es la forma de ver que la pagina
  /// sigue y de arrastrarla. En celulares y tablets (tambien en su
  /// navegador) solo aparece mientras se desliza, como es costumbre ahi.
  bool _conBarraFija() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    if (controlador.cargandoInicial) {
      return const _PantallaCarga();
    }

    final conBarraFija = _conBarraFija();

    return Scaffold(
      backgroundColor: ColoresOnix.azulProfundo,
      // SizedBox.expand es imprescindible: `Scaffold` entrega al body un alto
      // suelto, y un `Stack` asi se encoge hasta la barra de navegacion
      // (88 px). Sin esto, la pagina queda comprimida en esa franja.
      body: SizedBox.expand(
        // La barra de desplazamiento envuelve toda la pantalla para quedar
        // por encima de la barra de navegacion, que si no le tapa la punta.
        // Se dibuja una sola vez: la automatica de Flutter se apaga abajo.
        child: Scrollbar(
          key: const Key('barra-desplazamiento'),
          controller: _desplazador,
          thumbVisibility: conBarraFija,
          trackVisibility: conBarraFija,
          interactive: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _desplazador,
                    primary: false,
                    child: Column(
                      children: [
                        ...widget.secciones,
                        const PiePagina(),
                      ],
                    ),
                  ),
                ),
              ),
              BarraNavegacion(
                desplazador: _desplazador,
                paginaActual: widget.pagina,
              ),
              DistintivoOrigenDatos(arranque: widget.arranque),
            ],
          ),
        ),
      ),
    );
  }
}

/// Franja oscura con el titulo de una pantalla secundaria. Deja espacio
/// arriba para la barra de navegacion, que es transparente al inicio.
class EncabezadoPantalla extends StatelessWidget {
  const EncabezadoPantalla({
    super.key,
    required this.etiqueta,
    required this.titulo,
    required this.bajada,
  });

  final String etiqueta;
  final String titulo;
  final String bajada;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);

    return SeccionPagina(
      gradiente: GradientesOnix.fondoOscuro,
      espacioSuperior: esMovil ? 118 : 150,
      espacioInferior: esMovil ? 44 : 64,
      child: Aparicion(
        child: Column(
          children: [
            PildoraEtiqueta(texto: etiqueta, sobreFondoOscuro: true),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: PuntosQuiebre.esMovilChico(context)
                        ? 32
                        : (esMovil ? 36 : 52),
                    color: ColoresOnix.blanco,
                  ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                bajada,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ColoresOnix.sobreAzulSuave,
                      fontSize: esMovil ? 15.5 : 17,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lleva al inicio, donde estan el formulario y el panel.
void irAParticipar(BuildContext contexto) =>
    NavegacionOnix.ir(contexto, PaginaOnix.inicio);

class _PantallaCarga extends StatelessWidget {
  const _PantallaCarga();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: GradientesOnix.fondoOscuro),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoOnix(alto: 62, sobreFondoOscuro: true),
            SizedBox(height: 30),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: ColoresOnix.amarilloOnix,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
