import 'package:flutter/material.dart';

import '../../app.dart';
import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/grilla_uniforme.dart';
import '../componentes/indicadores.dart';
import '../componentes/seccion_pagina.dart';
import '../premio/caja_regalo.dart';

/// Los premios: tres cajas cerradas y lo que puede salir de cada una.
class SeccionPremios extends StatelessWidget {
  const SeccionPremios({super.key});

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final columnas = esMovil ? 1 : 3;
    final participante = ProveedorCampana.de(context).participante;

    return SeccionPagina(
      fondo: ColoresOnix.fondo,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'Premios',
            titulo: 'Tres cajas cerradas. Una es tuya.',
            bajada:
                'Con ${ConfigCampana.metaTickets} tickets reclamas tu premio y '
                'eliges una de tres cajas. Cada una esconde un premio distinto '
                'y el orden cambia en cada reclamo: nadie sabe cuál es cuál '
                'hasta que la abres.',
          ),
          const SizedBox(height: 50),
          Aparicion(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _VitrinaCajas(tamano: esMovil ? 86 : 124),
            ),
          ),
          const SizedBox(height: 46),
          GrillaUniforme(
            columnas: columnas,
            children: [
              for (var i = 0; i < PremioCaja.values.length; i++)
                Aparicion(
                  retraso: Duration(milliseconds: 80 * i),
                  child: _TarjetaPremio(premio: PremioCaja.values[i]),
                ),
            ],
          ),
          if (participante != null) ...[
            const SizedBox(height: 34),
            Aparicion(child: _MiAvance(participante: participante)),
          ],
        ],
      ),
    );
  }
}

/// Las tres cajas tal como aparecen al reclamar: azul, amarilla y azul.
class _VitrinaCajas extends StatelessWidget {
  const _VitrinaCajas({required this.tamano});

  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        tamano * 0.35,
        tamano * 0.4,
        tamano * 0.35,
        tamano * 0.25,
      ),
      decoration: BoxDecoration(
        gradient: GradientesOnix.fondoOscuro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioExtra),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, estilo)
                  in [EstiloCaja.azul, EstiloCaja.amarilla, EstiloCaja.azul]
                      .indexed) ...[
                if (i > 0) SizedBox(width: tamano * 0.28),
                CajaRegalo(tamano: tamano, estilo: estilo),
              ],
            ],
          ),
          SizedBox(height: tamano * 0.22),
          const Text(
            '¿Cuál abrirás?',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.amarilloOnix,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPremio extends StatelessWidget {
  const _TarjetaPremio({required this.premio});

  final PremioCaja premio;

  @override
  Widget build(BuildContext context) {
    return ElevacionAlPasar(
      constructor: (contexto, activo) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ColoresOnix.blanco,
          borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
          border: Border.all(
            color: activo ? ColoresOnix.amarilloOnix : ColoresOnix.borde,
            width: activo ? 1.6 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                gradient: GradientesOnix.fondoOscuro,
                shape: BoxShape.circle,
              ),
              child: Icon(
                premio.icono,
                color: ColoresOnix.amarilloOnix,
                size: 25,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'PUEDE TOCARTE',
              style: TextStyle(
                color: ColoresOnix.textoSuave,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              premio.titulo,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: ColoresOnix.texto,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              premio.detalle,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: ColoresOnix.textoSuave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio del avance para quien ya inicio sesion.
class _MiAvance extends StatelessWidget {
  const _MiAvance({required this.participante});

  final Participante participante;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ColoresOnix.blanco,
          borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
          border: Border.all(color: ColoresOnix.borde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              participante.llegoALaMeta
                  ? '¡Ya tienes tus ${ConfigCampana.metaTickets} tickets! '
                      'Reclama tu premio desde tu panel.'
                  : 'Llevas ${participante.tickets} de '
                      '${ConfigCampana.metaTickets} tickets',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ColoresOnix.texto,
              ),
            ),
            const SizedBox(height: 12),
            BarraProgresoMeta(
              valor: participante.tickets,
              meta: ConfigCampana.metaTickets,
              alto: 10,
            ),
          ],
        ),
      ),
    );
  }
}
