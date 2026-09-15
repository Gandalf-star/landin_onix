import 'package:flutter/material.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/logo_onix.dart';
import '../componentes/seccion_pagina.dart';

/// Pie de pagina con marca, contacto y avisos legales.
class PiePagina extends StatelessWidget {
  const PiePagina({super.key});

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final anio = DateTime.now().year;

    const marca = LogoOnix(alto: 36, sobreFondoOscuro: true);
    Text lema(TextAlign alineacion) => Text(
      'Movilidad donde tú pones el precio. '
      'Campaña válida en Chile.',
      textAlign: alineacion,
      style: const TextStyle(
        color: ColoresOnix.sobreAzulSuave,
        fontSize: 13.5,
        height: 1.6,
      ),
    );
    const campana = <String>[
      'Bases y condiciones',
      'Política de privacidad',
      'Cómo se reclama el premio',
    ];
    final soporte = <String>[
      'WhatsApp ${ConfigCampana.whatsappSoporte}',
      'ayuda@onixdrive.cl',
      'Reportar una trampa',
    ];
    final derechos = Text(
      '© $anio ${ConfigCampana.nombreMarca}. Todos los derechos reservados.',
      textAlign: esMovil ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        color: ColoresOnix.sobreAzulSuave,
        fontSize: 12.5,
      ),
    );
    final gratis = Text(
      'Participar es gratis · No se solicita ningún pago',
      textAlign: esMovil ? TextAlign.center : TextAlign.end,
      style: const TextStyle(
        color: ColoresOnix.amarilloOnix,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );

    return SeccionPagina(
      fondo: ColoresOnix.azulProfundo,
      espacioSuperior: 56,
      espacioInferior: 40,
      child: esMovil
          // En celular todo va centrado: marca, lema y las dos columnas de
          // enlaces una bajo la otra, sin bloques cargados a la izquierda.
          ? Column(
              children: [
                marca,
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: lema(TextAlign.center),
                ),
                const SizedBox(height: 34),
                const _ColumnaPie(
                  titulo: 'Campaña',
                  enlaces: campana,
                  centrada: true,
                ),
                const SizedBox(height: 18),
                _ColumnaPie(titulo: 'Soporte', enlaces: soporte, centrada: true),
                const SizedBox(height: 30),
                Container(height: 1, color: ColoresOnix.bordeSobreAzul),
                const SizedBox(height: 22),
                derechos,
                const SizedBox(height: 10),
                gratis,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          marca,
                          const SizedBox(height: 16),
                          SizedBox(width: 300, child: lema(TextAlign.start)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 40),
                    const Expanded(
                      flex: 2,
                      child: _ColumnaPie(titulo: 'Campaña', enlaces: campana),
                    ),
                    const SizedBox(width: 40),
                    Expanded(
                      flex: 2,
                      child: _ColumnaPie(titulo: 'Soporte', enlaces: soporte),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Container(height: 1, color: ColoresOnix.bordeSobreAzul),
                const SizedBox(height: 22),
                // Derechos a la izquierda y aviso a la derecha, cada uno
                // pegado a su borde (un Wrap los dejaba juntos a la izquierda).
                Row(
                  children: [
                    Expanded(child: derechos),
                    const SizedBox(width: 24),
                    Expanded(child: gratis),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ColumnaPie extends StatelessWidget {
  const _ColumnaPie({
    required this.titulo,
    required this.enlaces,
    this.centrada = false,
  });

  final String titulo;
  final List<String> enlaces;
  final bool centrada;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          centrada ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          titulo.toUpperCase(),
          style: const TextStyle(
            color: ColoresOnix.blanco,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        for (final enlace in enlaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              enlace,
              textAlign: centrada ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                color: ColoresOnix.sobreAzulSuave,
                fontSize: 13.5,
              ),
            ),
          ),
      ],
    );
  }
}
