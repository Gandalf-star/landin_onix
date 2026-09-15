import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/botones.dart';
import '../componentes/efectos.dart';
import '../componentes/logo_onix.dart';
import '../componentes/seccion_pagina.dart';

/// El objetivo real de la campana: que la gente conozca y descargue la app.
class SeccionOnixDrive extends StatelessWidget {
  const SeccionOnixDrive({super.key});

  @override
  Widget build(BuildContext context) {
    final esEscritorio = PuntosQuiebre.esEscritorio(context);

    return SeccionPagina(
      fondo: ColoresOnix.blanco,
      child: esEscritorio
          ? const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: _DiscursoApp()),
                SizedBox(width: 60),
                Expanded(flex: 5, child: Center(child: _MaquetaTelefono())),
              ],
            )
          // En celular y tablet el discurso va centrado sobre la maqueta.
          : const Column(
              children: [
                _DiscursoApp(centrado: true),
                SizedBox(height: 48),
                _MaquetaTelefono(),
              ],
            ),
    );
  }
}

class _DiscursoApp extends StatelessWidget {
  const _DiscursoApp({this.centrado = false});

  final bool centrado;

  @override
  Widget build(BuildContext context) {
    const ventajas = <(IconData, String, String)>[
      (
        Icons.price_change_rounded,
        'Pon tu precio',
        'Propones cuánto quieres pagar y los conductores cerca deciden.',
      ),
      (
        Icons.shield_rounded,
        'Conductores verificados',
        'Documentos, antecedentes y vehículo revisados antes de manejar.',
      ),
      (
        Icons.bolt_rounded,
        'Sin sorpresas al final',
        'Ves el precio antes de subirte y pagas como prefieras.',
      ),
    ];

    final android = BotonDorado(
      texto: 'Descargar para Android',
      icono: Icons.android_rounded,
      expandido: true,
      alPresionar: () => _abrir(ConfigCampana.urlPlayStore),
    );
    final iphone = BotonFantasma(
      texto: 'Descargar para iPhone',
      icono: Icons.apple_rounded,
      sobreFondoOscuro: false,
      expandido: true,
      alPresionar: () => _abrir(ConfigCampana.urlAppStore),
    );

    return Column(
      crossAxisAlignment:
          centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Aparicion(
          child: EncabezadoSeccion(
            etiqueta: 'La plataforma',
            titulo: 'Esta campaña existe por Onix Drive',
            bajada:
                'Onix Drive es la app de movilidad donde tú pones el precio '
                'de tu viaje. Los premios son nuestra forma de invitarte a '
                'probarla y de agradecer a quien nos recomienda.',
            alineacion: centrado
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
          ),
        ),
        const SizedBox(height: 34),
        // Las ventajas y los botones comparten un mismo ancho: centrados en
        // celular y tablet, alineados con el titulo en escritorio.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: centrado ? 560 : 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < ventajas.length; i++)
                Aparicion(
                  retraso: Duration(milliseconds: 80 * i),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _Ventaja(
                      icono: ventajas[i].$1,
                      titulo: ventajas[i].$2,
                      detalle: ventajas[i].$3,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              // Los dos botones siempre del mismo ancho: lado a lado si
              // caben, uno sobre otro en celulares.
              LayoutBuilder(
                builder: (contexto, restricciones) =>
                    restricciones.maxWidth >= 480
                        ? Row(
                            children: [
                              Expanded(child: android),
                              const SizedBox(width: 12),
                              Expanded(child: iphone),
                            ],
                          )
                        : Column(
                            children: [
                              android,
                              const SizedBox(height: 12),
                              iphone,
                            ],
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _abrir(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _Ventaja extends StatelessWidget {
  const _Ventaja({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: GradientesOnix.fondoOscuro,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, size: 19, color: ColoresOnix.amarilloOnix),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ColoresOnix.texto,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detalle,
                style: const TextStyle(
                  color: ColoresOnix.textoSuave,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Maqueta de telefono dibujada en Flutter: evita depender de capturas que
/// envejecen cada vez que cambia la app.
class _MaquetaTelefono extends StatelessWidget {
  const _MaquetaTelefono();

  @override
  Widget build(BuildContext context) {
    return Aparicion(
      retraso: const Duration(milliseconds: 160),
      child: Container(
        width: 288,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ColoresOnix.azulProfundo,
          borderRadius: BorderRadius.circular(42),
          boxShadow: [
            BoxShadow(
              color: ColoresOnix.azulOnix.withValues(alpha: 0.28),
              blurRadius: 50,
              offset: const Offset(0, 26),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          decoration: BoxDecoration(
            gradient: GradientesOnix.fondoOscuro,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoOnix(alto: 30, sobreFondoOscuro: true),
              const SizedBox(height: 26),
              const Text(
                '¿A dónde vamos?',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  color: ColoresOnix.blanco,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              _CampoFalso(
                icono: Icons.my_location_rounded,
                texto: 'Providencia 1234',
                color: ColoresOnix.verde,
              ),
              const SizedBox(height: 9),
              _CampoFalso(
                icono: Icons.location_on_rounded,
                texto: 'Aeropuerto SCL',
                color: ColoresOnix.amarilloOnix,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ColoresOnix.blanco.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ColoresOnix.bordeSobreAzul),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TU OFERTA',
                      style: TextStyle(
                        color: ColoresOnix.sobreAzulSuave,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                        const Text(
                          '\$12.400',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: ColoresOnix.amarilloOnix,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                          const Text(
                            'CLP',
                            style: TextStyle(
                              color: ColoresOnix.sobreAzulSuave,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: GradientesOnix.dorado,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  'Buscar conductor',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: ColoresOnix.azulOnix,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampoFalso extends StatelessWidget {
  const _CampoFalso({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: ColoresOnix.blanco.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresOnix.bordeSobreAzul),
      ),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ColoresOnix.sobreAzul,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
