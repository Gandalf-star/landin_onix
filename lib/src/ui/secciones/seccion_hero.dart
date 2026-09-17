import 'package:flutter/material.dart';

import '../../app.dart';
import '../../datos/controlador_referidos.dart';
import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/grilla_uniforme.dart';
import '../componentes/seccion_pagina.dart';
import '../panel/panel_participante.dart';
import '../registro/tarjeta_participacion.dart';

/// Primera pantalla: promesa de la campana + tarjeta para participar.
class SeccionHero extends StatelessWidget {
  const SeccionHero({super.key});

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final esEscritorio = PuntosQuiebre.esEscritorio(context);

    return Stack(
      children: [
        const Positioned.fill(child: _FondoHero()),
        SeccionPagina(
          espacioSuperior: esMovil ? 118 : 152,
          espacioInferior: esMovil ? 64 : 96,
          child: esEscritorio
              ? const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: _DiscursoHero(centrado: false)),
                    SizedBox(width: 56),
                    Expanded(flex: 5, child: _TarjetaLateral()),
                  ],
                )
              // En celular y tablet todo va en una columna centrada: el
              // discurso arriba y la tarjeta debajo, con un ancho comodo
              // para leer y escribir aunque la pantalla sea ancha.
              : Column(
                  children: [
                    const _DiscursoHero(centrado: true),
                    const SizedBox(height: 44),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: const SizedBox(
                          width: double.infinity,
                          child: _TarjetaLateral(),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Fondo azul Onix con un halo azul difuminado abajo a la izquierda.
class _FondoHero extends StatelessWidget {
  const _FondoHero();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: GradientesOnix.fondoOscuro),
      child: Stack(
        children: [
          Positioned(
            bottom: -220,
            left: -160,
            child: _Halo(
              diametro: 600,
              color: ColoresOnix.azulElectrico.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.diametro, required this.color});

  final double diametro;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _DiscursoHero extends StatelessWidget {
  const _DiscursoHero({required this.centrado});

  /// En celular y tablet el discurso va centrado; en escritorio, alineado a
  /// la izquierda junto a la tarjeta.
  final bool centrado;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final alineacionTexto = centrado ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment:
          centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Aparicion(
          child: PildoraEtiqueta(
            texto: '${ConfigCampana.nombreCampana} · ${ConfigCampana.pais}',
            icono: Icons.bolt_rounded,
            sobreFondoOscuro: true,
          ),
        ),
        const SizedBox(height: 26),
        Aparicion(
          retraso: const Duration(milliseconds: 90),
          child: Text.rich(
            textAlign: alineacionTexto,
            TextSpan(
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: PuntosQuiebre.esMovilChico(context)
                        ? 38
                        : (esMovil ? 42 : 66),
                    color: ColoresOnix.blanco,
                  ),
              children: const [
                TextSpan(text: 'Invita a '),
                TextSpan(
                  text: '${ConfigCampana.metaTickets}',
                  style: TextStyle(color: ColoresOnix.amarilloOnix),
                ),
                TextSpan(text: '.\nAbre tu caja premiada.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Aparicion(
          retraso: const Duration(milliseconds: 160),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(
              'Comparte tu link por WhatsApp: cada contacto que lo abre recibe '
              'su propio código. Cuando lo valida desde su celular sumas un '
              'ticket, y con ${ConfigCampana.metaTickets} tickets eliges una de '
              'tres cajas cerradas: te llevas el premio que esconde.',
              textAlign: alineacionTexto,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ColoresOnix.sobreAzulSuave,
                    fontSize: esMovil ? 16 : 18,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        Aparicion(
          retraso: const Duration(milliseconds: 240),
          child: _PremiosEnJuego(centrado: centrado),
        ),
      ],
    );
  }
}

/// Los tres premios que pueden salir de las cajas, en lugar de contadores.
///
/// Van en tres casillas del mismo ancho y alto: en cualquier pantalla se ven
/// alineadas, sin que la tercera pildora caiga sola a otra linea.
class _PremiosEnJuego extends StatelessWidget {
  const _PremiosEnJuego({required this.centrado});

  final bool centrado;

  @override
  Widget build(BuildContext context) {
    final chico = PuntosQuiebre.esMovilChico(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment:
            centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          const Text(
            'EN LAS CAJAS TE PUEDE TOCAR',
            style: TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          GrillaUniforme(
            columnas: PremioCaja.values.length,
            separacion: chico ? 8 : 10,
            children: [
              for (final premio in PremioCaja.values)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: chico ? 6 : 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: ColoresOnix.blanco.withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(MedidasOnix.radioMedio),
                    border: Border.all(color: ColoresOnix.bordeSobreAzul),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              ColoresOnix.amarilloOnix.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          premio.icono,
                          size: 17,
                          color: ColoresOnix.amarilloOnix,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        premio.titulo,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          color: ColoresOnix.blanco,
                          fontSize: chico ? 12.5 : 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Muestra el formulario de participacion o, si ya hay sesion, el panel.
class _TarjetaLateral extends StatelessWidget {
  const _TarjetaLateral();

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);

    return Aparicion(
      retraso: const Duration(milliseconds: 200),
      desplazamiento: 34,
      child: controlador.etapa == EtapaRegistro.listo &&
              controlador.participante != null
          ? const PanelParticipante()
          : const TarjetaParticipacion(),
    );
  }
}
