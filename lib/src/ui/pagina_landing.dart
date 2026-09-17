import 'package:flutter/material.dart';

import '../nucleo/arranque.dart';
import 'estructura_pagina.dart';
import 'navegacion.dart';
import 'secciones/seccion_como_funciona.dart';
import 'secciones/seccion_cta_final.dart';
import 'secciones/seccion_hero.dart';
import 'secciones/seccion_onix_drive.dart';
import 'secciones/seccion_premios.dart';
import 'secciones/seccion_reclamo.dart';

/// Inicio: la promesa de la campana con el formulario (o el panel de quien
/// ya tiene sesion). Lo demas vive en pantallas propias, a un toque desde la
/// barra de navegacion, para que la pagina no sea eterna hacia abajo.
class PaginaLanding extends StatelessWidget {
  const PaginaLanding({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  Widget build(BuildContext context) {
    return EstructuraPagina(
      pagina: PaginaOnix.inicio,
      arranque: arranque,
      secciones: const [SeccionHero()],
    );
  }
}

/// Los cuatro pasos, de crear la cuenta a abrir la caja.
class PaginaComoFunciona extends StatelessWidget {
  const PaginaComoFunciona({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  Widget build(BuildContext context) {
    return EstructuraPagina(
      pagina: PaginaOnix.comoFunciona,
      arranque: arranque,
      secciones: [
        const EncabezadoPantalla(
          etiqueta: 'Cómo funciona',
          titulo: 'De tu WhatsApp a tu caja premiada',
          bajada: 'Creas tu cuenta, compartes tu link y cada contacto que '
              'valida su código desde su celular te suma un ticket.',
        ),
        const SeccionComoFunciona(),
        SeccionCtaFinal(alParticipar: () => irAParticipar(context)),
      ],
    );
  }
}

/// Las tres cajas y como se reclama y entrega el premio.
class PaginaPremios extends StatelessWidget {
  const PaginaPremios({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  Widget build(BuildContext context) {
    return EstructuraPagina(
      pagina: PaginaOnix.premios,
      arranque: arranque,
      secciones: [
        const EncabezadoPantalla(
          etiqueta: 'Premios',
          titulo: 'Tres cajas, un premio para ti',
          bajada: 'Un viaje gratis, un regalo Onix o saldo Onix. Así se '
              'reclaman, se abren y se entregan.',
        ),
        const SeccionPremios(),
        const SeccionReclamo(),
        SeccionCtaFinal(alParticipar: () => irAParticipar(context)),
      ],
    );
  }
}

/// La app de movilidad que promociona la campana.
class PaginaOnixDrive extends StatelessWidget {
  const PaginaOnixDrive({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  Widget build(BuildContext context) {
    return EstructuraPagina(
      pagina: PaginaOnix.onixDrive,
      arranque: arranque,
      secciones: [
        const EncabezadoPantalla(
          etiqueta: 'Onix Drive',
          titulo: 'Muévete a tu precio',
          bajada: 'La plataforma de movilidad detrás del Reto 50 Onix. '
              'Descárgala y úsala con tu premio.',
        ),
        const SeccionOnixDrive(),
        SeccionCtaFinal(alParticipar: () => irAParticipar(context)),
      ],
    );
  }
}

/// Pantalla que corresponde a cada direccion.
Widget paginaPara(PaginaOnix pagina, ResultadoArranque arranque) =>
    switch (pagina) {
      PaginaOnix.inicio => PaginaLanding(arranque: arranque),
      PaginaOnix.comoFunciona => PaginaComoFunciona(arranque: arranque),
      PaginaOnix.premios => PaginaPremios(arranque: arranque),
      PaginaOnix.onixDrive => PaginaOnixDrive(arranque: arranque),
    };
