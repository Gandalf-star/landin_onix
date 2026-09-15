import 'package:flutter/material.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/grilla_uniforme.dart';
import '../componentes/indicadores.dart';
import '../componentes/seccion_pagina.dart';

/// Explica en publico el momento de reclamar el premio y como se valida.
/// La transparencia es parte del diseno anti-trampa: si queda claro que las
/// cajas estan selladas en el servidor y que cada ticket se verifica,
/// intentar hacer trampa deja de ser atractivo.
class SeccionReclamo extends StatelessWidget {
  const SeccionReclamo({super.key});

  @override
  Widget build(BuildContext context) {
    final esEscritorio = PuntosQuiebre.esEscritorio(context);
    final columnas =
        esEscritorio ? 4 : (PuntosQuiebre.esMovil(context) ? 1 : 2);
    const pasos = ConfigCampana.pasosReclamo;

    return SeccionPagina(
      gradiente: GradientesOnix.fondoOscuro,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'El reclamo',
            titulo: 'Del ticket 50 a tu premio, sin trucos',
            bajada:
                'Así funciona el momento de abrir tu caja y por qué nadie '
                'puede saber de antemano dónde está cada premio.',
            sobreFondoOscuro: true,
          ),
          const SizedBox(height: 54),
          GrillaUniforme(
            columnas: columnas,
            separacion: esEscritorio ? 20 : 16,
            children: [
              for (var i = 0; i < pasos.length; i++)
                Aparicion(
                  retraso: Duration(milliseconds: 90 * i),
                  child: _PasoReclamo(
                    numero: pasos[i].$1,
                    titulo: pasos[i].$2,
                    detalle: pasos[i].$3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 34),
          const Aparicion(
            retraso: Duration(milliseconds: 380),
            child: _NotaValidacion(),
          ),
        ],
      ),
    );
  }
}

class _PasoReclamo extends StatelessWidget {
  const _PasoReclamo({
    required this.numero,
    required this.titulo,
    required this.detalle,
  });

  final String numero;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return TarjetaVidrio(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            numero,
            style: const TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.amarilloOnix,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            style: const TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.blanco,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            detalle,
            style: const TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotaValidacion extends StatelessWidget {
  const _NotaValidacion();

  @override
  Widget build(BuildContext context) {
    return TarjetaVidrio(
      destacada: true,
      padding: const EdgeInsets.all(24),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_rounded,
            color: ColoresOnix.amarilloOnix,
            size: 24,
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  color: ColoresOnix.sobreAzul,
                  fontSize: 14,
                  height: 1.6,
                ),
                children: [
                  TextSpan(
                    text: 'Cómo validamos tu premio. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ColoresOnix.blanco,
                    ),
                  ),
                  TextSpan(
                    text: 'Cada ticket ganador tiene un código de '
                        'confirmación único que queda registrado junto a la '
                        'caja que abriste. Antes de entregar, el equipo Onix '
                        'revisa ese código, los números de tus invitados y '
                        'los dispositivos anclados a cada invitación. Si todo '
                        'está en regla, te contactamos al número verificado '
                        'de tu cuenta.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
