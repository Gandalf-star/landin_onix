import 'package:flutter/material.dart';

import '../../nucleo/tema_onix.dart';
import 'efectos.dart';

/// Contenedor estandar de una seccion: ancho maximo, respiracion vertical y
/// fondo opcional oscuro o crema.
class SeccionPagina extends StatelessWidget {
  const SeccionPagina({
    super.key,
    required this.child,
    this.fondo,
    this.gradiente,
    this.espacioSuperior,
    this.espacioInferior,
    this.anchoMaximo = MedidasOnix.anchoMaximoContenido,
  });

  final Widget child;
  final Color? fondo;
  final Gradient? gradiente;
  final double? espacioSuperior;
  final double? espacioInferior;
  final double anchoMaximo;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final vertical = esMovil
        ? MedidasOnix.espacioSeccionMovil
        : MedidasOnix.espacioSeccionEscritorio;
    final horizontal = PuntosQuiebre.esMovilChico(context)
        ? 16.0
        : (esMovil ? 20.0 : 32.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: fondo, gradient: gradiente),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        espacioSuperior ?? vertical,
        horizontal,
        espacioInferior ?? vertical,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: anchoMaximo),
          child: child,
        ),
      ),
    );
  }
}

/// Encabezado reutilizable: pildora + titulo + bajada.
class EncabezadoSeccion extends StatelessWidget {
  const EncabezadoSeccion({
    super.key,
    required this.etiqueta,
    required this.titulo,
    this.bajada,
    this.sobreFondoOscuro = false,
    this.alineacion = CrossAxisAlignment.center,
  });

  final String etiqueta;
  final String titulo;
  final String? bajada;
  final bool sobreFondoOscuro;
  final CrossAxisAlignment alineacion;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final centrado = alineacion == CrossAxisAlignment.center;
    final colorTitulo =
        sobreFondoOscuro ? ColoresOnix.blanco : ColoresOnix.texto;
    final colorBajada =
        sobreFondoOscuro ? ColoresOnix.sobreAzulSuave : ColoresOnix.textoSuave;

    return Aparicion(
      child: Column(
        crossAxisAlignment: alineacion,
        children: [
          PildoraEtiqueta(
            texto: etiqueta,
            sobreFondoOscuro: sobreFondoOscuro,
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              titulo,
              textAlign: centrado ? TextAlign.center : TextAlign.start,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(
                    fontSize: esMovil ? 30 : 44,
                    color: colorTitulo,
                  ),
            ),
          ),
          if (bajada != null) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Text(
                bajada!,
                textAlign: centrado ? TextAlign.center : TextAlign.start,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: colorBajada),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pildora pequena de etiqueta ("Cómo funciona", "Premios"...).
class PildoraEtiqueta extends StatelessWidget {
  const PildoraEtiqueta({
    super.key,
    required this.texto,
    this.icono,
    this.sobreFondoOscuro = false,
  });

  final String texto;
  final IconData? icono;
  final bool sobreFondoOscuro;

  @override
  Widget build(BuildContext context) {
    final fondo = sobreFondoOscuro
        ? ColoresOnix.amarilloOnix.withValues(alpha: 0.14)
        : ColoresOnix.amarilloClaro;
    final colorTexto =
        sobreFondoOscuro ? ColoresOnix.amarilloOnix : ColoresOnix.azulOnix;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: sobreFondoOscuro
              ? ColoresOnix.amarilloOnix.withValues(alpha: 0.35)
              : ColoresOnix.amarilloOnix.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 15, color: colorTexto),
            const SizedBox(width: 7),
          ],
          Text(
            texto.toUpperCase(),
            style: TextStyle(
              color: colorTexto,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
