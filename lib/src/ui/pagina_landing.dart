import 'package:flutter/material.dart';

import '../app.dart';
import '../nucleo/arranque.dart';
import '../nucleo/tema_onix.dart';
import 'componentes/distintivo_origen_datos.dart';
import 'componentes/logo_onix.dart';
import 'secciones/barra_navegacion.dart';
import 'secciones/pie_pagina.dart';
import 'secciones/seccion_como_funciona.dart';
import 'secciones/seccion_cta_final.dart';
import 'secciones/seccion_hero.dart';
import 'secciones/seccion_juego_limpio.dart';
import 'secciones/seccion_onix_drive.dart';
import 'secciones/seccion_premios.dart';
import 'secciones/seccion_preguntas.dart';
import 'secciones/seccion_ranking.dart';
import 'secciones/seccion_reclamo.dart';

/// Pagina unica de la campana: hero con formulario, explicacion, las tres
/// cajas del premio, como se reclama, ranking, reglas de juego limpio y
/// promocion de Onix Drive.
class PaginaLanding extends StatefulWidget {
  const PaginaLanding({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  State<PaginaLanding> createState() => _PaginaLandingState();
}

class _PaginaLandingState extends State<PaginaLanding> {
  final _desplazador = ScrollController();

  final _claveInicio = GlobalKey();
  final _claveComoFunciona = GlobalKey();
  final _clavePremios = GlobalKey();
  final _claveRanking = GlobalKey();
  final _clavePreguntas = GlobalKey();

  @override
  void dispose() {
    _desplazador.dispose();
    super.dispose();
  }

  void _irA(GlobalKey clave) {
    final contexto = clave.currentContext;
    if (contexto == null) return;
    Scrollable.ensureVisible(
      contexto,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);

    if (controlador.cargandoInicial) {
      return const _PantallaCarga();
    }

    return Scaffold(
      // SizedBox.expand es imprescindible, no decorativo: `Scaffold` entrega
      // al body restricciones de alto sueltas, y un `Stack` con alto suelto
      // se encoge hasta su hijo NO posicionado mas grande, que aqui es la
      // barra de navegacion (88 px). Sin esto, el `Positioned.fill` de abajo
      // rellena solo esos 88 px y toda la landing queda comprimida en una
      // franja del alto del encabezado.
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _desplazador,
                child: Column(
                  children: [
                    SeccionHero(key: _claveInicio),
                    SeccionComoFunciona(key: _claveComoFunciona),
                    SeccionPremios(key: _clavePremios),
                    const SeccionReclamo(),
                    SeccionRanking(key: _claveRanking),
                    const SeccionJuegoLimpio(),
                    const SeccionOnixDrive(),
                    SeccionPreguntas(key: _clavePreguntas),
                    SeccionCtaFinal(alParticipar: () => _irA(_claveInicio)),
                    const PiePagina(),
                  ],
                ),
              ),
            ),
            BarraNavegacion(
              desplazador: _desplazador,
              alIrAInicio: () => _irA(_claveInicio),
              alIrAComoFunciona: () => _irA(_claveComoFunciona),
              alIrAPremios: () => _irA(_clavePremios),
              alIrARanking: () => _irA(_claveRanking),
              alIrAPreguntas: () => _irA(_clavePreguntas),
            ),
            DistintivoOrigenDatos(arranque: widget.arranque),
          ],
        ),
      ),
    );
  }
}

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
