import 'package:flutter/material.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/grilla_uniforme.dart';
import '../componentes/seccion_pagina.dart';

/// Los cuatro pasos del recorrido, del registro a la caja del premio.
class SeccionComoFunciona extends StatelessWidget {
  const SeccionComoFunciona({super.key});

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final esEscritorio = PuntosQuiebre.esEscritorio(context);
    final columnas = esEscritorio ? 4 : (esMovil ? 1 : 2);

    return SeccionPagina(
      fondo: ColoresOnix.blanco,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'Cómo funciona',
            titulo: 'Cuatro pasos hasta tu caja premiada',
            bajada:
                'Sin formularios eternos ni papeleo: tu número es tu entrada '
                'y cada invitado que valida su código desde su celular es un '
                'ticket más, sin crear cuenta.',
          ),
          const SizedBox(height: 54),
          GrillaUniforme(
            columnas: columnas,
            separacion: 22,
            children: [
              for (var i = 0; i < ConfigCampana.pasos.length; i++)
                Aparicion(
                  retraso: Duration(milliseconds: 90 * i),
                  child: _TarjetaPaso(
                    numero: i + 1,
                    icono: ConfigCampana.pasos[i].$1,
                    titulo: ConfigCampana.pasos[i].$2,
                    descripcion: ConfigCampana.pasos[i].$3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaPaso extends StatelessWidget {
  const _TarjetaPaso({
    required this.numero,
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  final int numero;
  final IconData icono;
  final String titulo;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return ElevacionAlPasar(
      constructor: (contexto, activo) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: activo ? ColoresOnix.blanco : ColoresOnix.fondo,
          borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
          border: Border.all(
            color: activo ? ColoresOnix.amarilloOnix : ColoresOnix.borde,
            width: activo ? 1.6 : 1.2,
          ),
          boxShadow: activo
              ? [
                  BoxShadow(
                    color: ColoresOnix.azulOnix.withValues(alpha: 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: GradientesOnix.fondoOscuro,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icono, color: ColoresOnix.amarilloOnix, size: 22),
                ),
                const Spacer(),
                Text(
                  numero.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: ColoresOnix.borde,
                    height: 1,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 9),
            Text(
              descripcion,
              style: const TextStyle(
                color: ColoresOnix.textoSuave,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
