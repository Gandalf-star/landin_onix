import 'package:flutter/material.dart';

import '../../nucleo/tema_onix.dart';

/// Numero que cuenta desde cero hasta [valor] al aparecer.
class ContadorAnimado extends StatelessWidget {
  const ContadorAnimado({
    super.key,
    required this.valor,
    this.sufijo = '',
    this.estilo,
    this.duracion = const Duration(milliseconds: 1400),
  });

  final int valor;
  final String sufijo;
  final TextStyle? estilo;
  final Duration duracion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor.toDouble()),
      duration: duracion,
      curve: Curves.easeOutExpo,
      builder: (contexto, animado, _) => Text(
        '${_conSeparadores(animado.round())}$sufijo',
        style: estilo,
      ),
    );
  }

  /// Separador de miles chileno: 1.245.
  static String _conSeparadores(int numero) {
    final texto = numero.toString();
    final partes = <String>[];
    for (var i = texto.length; i > 0; i -= 3) {
      partes.insert(0, texto.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return partes.join('.');
  }
}

/// Tarjeta translucida para usar sobre el fondo azul del hero.
class TarjetaVidrio extends StatelessWidget {
  const TarjetaVidrio({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radio = MedidasOnix.radioGrande,
    this.destacada = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radio;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ColoresOnix.blanco.withValues(alpha: destacada ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(
          color: destacada
              ? ColoresOnix.amarilloOnix.withValues(alpha: 0.55)
              : ColoresOnix.bordeSobreAzul,
          width: destacada ? 1.6 : 1.2,
        ),
      ),
      child: child,
    );
  }
}

/// Barra de progreso hacia la meta, con los hitos de cada nivel marcados.
class BarraProgresoMeta extends StatelessWidget {
  const BarraProgresoMeta({
    super.key,
    required this.valor,
    required this.meta,
    this.hitos = const [],
    this.sobreFondoOscuro = false,
    this.alto = 14,
  });

  final int valor;
  final int meta;
  final List<int> hitos;
  final bool sobreFondoOscuro;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final avance = (valor / meta).clamp(0.0, 1.0);
    final fondoBarra = sobreFondoOscuro
        ? ColoresOnix.blanco.withValues(alpha: 0.12)
        : ColoresOnix.bordeClaro;

    return LayoutBuilder(
      builder: (contexto, restricciones) {
        final ancho = restricciones.maxWidth;
        return SizedBox(
          height: alto,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: fondoBarra,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: avance),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (contexto, animado, _) => FractionallySizedBox(
                  widthFactor: animado == 0 ? 0.001 : animado,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: GradientesOnix.dorado,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color:
                              ColoresOnix.amarilloOnix.withValues(alpha: 0.45),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final hito in hitos)
                if (hito < meta)
                  Positioned(
                    left: (ancho * (hito / meta)) - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: sobreFondoOscuro
                          ? ColoresOnix.azulProfundo.withValues(alpha: 0.65)
                          : ColoresOnix.blanco,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Etiqueta de estado (válido / pendiente / rechazado).
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado({
    super.key,
    required this.texto,
    required this.color,
    this.icono,
  });

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
