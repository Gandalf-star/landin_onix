import 'package:flutter/material.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/grilla_uniforme.dart';
import '../componentes/seccion_pagina.dart';

/// Reglas anti-trampa explicadas al publico.
///
/// Mostrarlas cumple dos funciones: da confianza a quien participa en serio y
/// desalienta a quien pensaba automatizar registros falsos.
class SeccionJuegoLimpio extends StatelessWidget {
  const SeccionJuegoLimpio({super.key});

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final esEscritorio = PuntosQuiebre.esEscritorio(context);
    final columnas = esEscritorio ? 3 : (esMovil ? 1 : 2);

    return SeccionPagina(
      fondo: ColoresOnix.fondo,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'Juego limpio',
            titulo: 'Un código, una persona, una sola vez',
            bajada:
                'Estas son las reglas que aplica el sistema de forma '
                'automática. No dependen de que alguien las revise a mano.',
          ),
          const SizedBox(height: 54),
          GrillaUniforme(
            columnas: columnas,
            children: [
              for (var i = 0; i < ConfigCampana.reglasJuegoLimpio.length; i++)
                Aparicion(
                  retraso: Duration(milliseconds: 60 * i),
                  child: _TarjetaRegla(
                    icono: ConfigCampana.reglasJuegoLimpio[i].$1,
                    titulo: ConfigCampana.reglasJuegoLimpio[i].$2,
                    detalle: ConfigCampana.reglasJuegoLimpio[i].$3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaRegla extends StatelessWidget {
  const _TarjetaRegla({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ColoresOnix.blanco,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
        border: Border.all(color: ColoresOnix.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ColoresOnix.amarilloClaro,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icono, size: 21, color: ColoresOnix.azulOnix),
          ),
          const SizedBox(height: 18),
          Text(
            titulo,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 9),
          Text(
            detalle,
            style: const TextStyle(
              color: ColoresOnix.textoSuave,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
