import 'package:flutter/material.dart';

import '../../app.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/botones.dart';
import '../componentes/efectos.dart';
import '../componentes/seccion_pagina.dart';

/// Ultimo llamado a la accion antes del pie de pagina.
class SeccionCtaFinal extends StatelessWidget {
  const SeccionCtaFinal({super.key, required this.alParticipar});

  final VoidCallback alParticipar;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final haySesion = ProveedorCampana.de(context).haySesion;

    return SeccionPagina(
      fondo: ColoresOnix.blanco,
      child: Aparicion(
        // El recorte va en la tarjeta y no en el Stack interno: asi el halo
        // se corta con la esquina redondeada y no deja un borde recto a la
        // vista en medio del bloque.
        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: GradientesOnix.fondoOscuro,
            borderRadius: BorderRadius.circular(MedidasOnix.radioExtra),
          ),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                right: -60,
                top: -60,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        ColoresOnix.amarilloOnix.withValues(alpha: 0.22),
                        ColoresOnix.amarilloOnix.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: esMovil ? 22 : 60,
                  vertical: esMovil ? 42 : 64,
                ),
                child: Column(
                  children: [
                    Text(
                      haySesion
                          ? 'Cada código que compartes es un ticket más'
                          : 'Tu próximo WhatsApp puede abrir una caja premiada',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: esMovil ? 27 : 40,
                            color: ColoresOnix.blanco,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Text(
                        'Participar toma menos de un minuto y es gratis. Con '
                        '${ConfigCampana.metaTickets} invitados verificados '
                        'eliges una de tres cajas y te llevas su premio.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ColoresOnix.sobreAzulSuave,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    BotonDorado(
                      texto: haySesion ? 'Ir a mi panel' : 'Quiero participar',
                      icono: Icons.arrow_upward_rounded,
                      alPresionar: alParticipar,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
