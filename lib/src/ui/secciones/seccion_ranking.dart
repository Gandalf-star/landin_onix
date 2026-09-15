import 'package:flutter/material.dart';

import '../../app.dart';
import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/indicadores.dart';
import '../componentes/seccion_pagina.dart';

/// Tabla publica de quienes van adelante. Los telefonos se muestran
/// enmascarados: sirve de prueba social sin exponer datos personales.
class SeccionRanking extends StatelessWidget {
  const SeccionRanking({super.key});

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final ranking = controlador.ranking;

    return SeccionPagina(
      fondo: ColoresOnix.blanco,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'Ranking',
            titulo: 'Quiénes van adelante',
            bajada:
                'Cada invitado verificado es un ticket y con '
                '${ConfigCampana.metaTickets} se abre la caja del premio. '
                'Mostramos el número parcialmente oculto para cuidar la '
                'privacidad.',
          ),
          const SizedBox(height: 46),
          Aparicion(
            child: Container(
              decoration: BoxDecoration(
                color: ColoresOnix.fondo,
                borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
                border: Border.all(color: ColoresOnix.borde),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < ranking.length; i++) ...[
                    _FilaRankingWidget(fila: ranking[i]),
                    if (i != ranking.length - 1)
                      const Divider(height: 1, indent: 20, endIndent: 20),
                  ],
                  if (ranking.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text(
                        'Todavía no hay participantes. Puedes ser el primero.',
                        style: TextStyle(color: ColoresOnix.textoSuave),
                      ),
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

class _FilaRankingWidget extends StatelessWidget {
  const _FilaRankingWidget({required this.fila});

  final FilaRanking fila;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final medalla = switch (fila.posicion) {
      1 => ColoresOnix.amarilloOnix,
      2 => const Color(0xFFB8C0CE),
      3 => const Color(0xFFCB8B5B),
      _ => null,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: esMovil ? 14 : 22,
        vertical: 15,
      ),
      decoration: BoxDecoration(
        color: fila.soyYo
            ? ColoresOnix.amarilloClaro.withValues(alpha: 0.6)
            : null,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medalla?.withValues(alpha: 0.18) ?? ColoresOnix.bordeClaro,
              shape: BoxShape.circle,
              border: medalla == null
                  ? null
                  : Border.all(color: medalla.withValues(alpha: 0.7)),
            ),
            child: Text(
              '${fila.posicion}',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: medalla ?? ColoresOnix.textoSuave,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fila.nombreVisible,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          color: ColoresOnix.texto,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (fila.soyYo) ...[
                      const SizedBox(width: 8),
                      const EtiquetaEstado(
                        texto: 'Tú',
                        color: ColoresOnix.azulElectrico,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  fila.telefonoEnmascarado,
                  style: const TextStyle(
                    color: ColoresOnix.textoSuave,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!esMovil) ...[
            SizedBox(
              width: 160,
              child: BarraProgresoMeta(
                valor: fila.referidosValidos,
                meta: ConfigCampana.metaTickets,
                alto: 8,
              ),
            ),
            const SizedBox(width: 18),
          ],
          SizedBox(
            width: 58,
            child: Text(
              '${fila.referidosValidos}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ColoresOnix.azulOnix,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
