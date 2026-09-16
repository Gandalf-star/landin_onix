import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../nucleo/tema_onix.dart';

/// Combinacion de colores de una caja.
enum EstiloCaja {
  /// Cuerpo rojo con cinta amarilla. Reemplaza al azul, que se perdia con
  /// el fondo oscuro del dialogo y de la seccion de premios.
  roja,

  /// Cuerpo amarillo Onix con cinta roja.
  amarilla;

  static const _rojoClaro = Color(0xFFF0474B);
  static const _rojoMedio = Color(0xFFD62828);
  static const _rojoOscuro = Color(0xFF9E1B1B);

  List<Color> get cuerpo => switch (this) {
        EstiloCaja.roja => const [_rojoClaro, _rojoMedio, _rojoOscuro],
        EstiloCaja.amarilla => const [
            ColoresOnix.amarilloIntenso,
            ColoresOnix.amarilloOnix,
            ColoresOnix.ambar,
          ],
      };

  List<Color> get tapa => switch (this) {
        EstiloCaja.roja => const [Color(0xFFFF5A5F), _rojoMedio],
        EstiloCaja.amarilla => const [
            Color(0xFFFFDB4D),
            ColoresOnix.amarilloIntenso,
          ],
      };

  List<Color> get cinta => switch (this) {
        EstiloCaja.roja => const [
            ColoresOnix.amarilloIntenso,
            ColoresOnix.ambar,
          ],
        EstiloCaja.amarilla => const [_rojoMedio, _rojoOscuro],
      };

  Color get borde => switch (this) {
        EstiloCaja.roja => ColoresOnix.amarilloOnix.withValues(alpha: 0.45),
        EstiloCaja.amarilla => ColoresOnix.blanco.withValues(alpha: 0.55),
      };
}

/// Caja de regalo dibujada con widgets, lista para animarse.
///
/// [apertura] va de 0 (cerrada) a 1 (tapa fuera): la tapa sube, gira y se
/// desvanece, y [contenido] asoma desde el interior. [brillo] enciende el
/// resplandor que sale de la caja abierta.
class CajaRegalo extends StatelessWidget {
  const CajaRegalo({
    super.key,
    required this.tamano,
    required this.estilo,
    this.apertura = 0,
    this.brillo = 0,
    this.contenido,
    this.inclinacionTapa = -1,
  });

  final double tamano;
  final EstiloCaja estilo;
  final double apertura;
  final double brillo;
  final Widget? contenido;

  /// Hacia donde gira la tapa al salir: -1 izquierda, 1 derecha.
  final double inclinacionTapa;

  @override
  Widget build(BuildContext context) {
    final ancho = tamano;
    final alto = tamano * 1.12;
    final anchoCuerpo = ancho * 0.8;
    final altoCuerpo = ancho * 0.6;
    final altoTapa = ancho * 0.19;
    final anchoTapa = ancho * 0.92;
    final superiorCuerpo = alto - altoCuerpo;
    final superiorTapa = superiorCuerpo - altoTapa + ancho * 0.01;

    final t = Curves.easeOutBack.transform(apertura.clamp(0.0, 1.0));
    final tLineal = apertura.clamp(0.0, 1.0);

    return SizedBox(
      width: ancho,
      height: alto,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Resplandor que sale de la caja abierta.
          if (brillo > 0)
            Positioned(
              left: -ancho * 0.35,
              right: -ancho * 0.35,
              top: superiorCuerpo - ancho * 0.75,
              height: ancho * 1.3,
              child: IgnorePointer(
                child: Opacity(
                  opacity: brillo.clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0xCCFFE680),
                          Color(0x55FFC700),
                          Color(0x00FFC700),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Sombra en el piso.
          Positioned(
            left: ancho * 0.14,
            right: ancho * 0.14,
            bottom: -ancho * 0.05,
            height: ancho * 0.1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ancho),
                gradient: RadialGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // Lo que asoma desde adentro.
          if (contenido != null && tLineal > 0)
            Positioned(
              left: 0,
              right: 0,
              top: superiorCuerpo - ancho * 0.42 * t,
              height: ancho * 0.5,
              child: Opacity(
                opacity: Curves.easeIn.transform(tLineal),
                child: Center(child: contenido),
              ),
            ),

          // Cuerpo.
          Positioned(
            left: (ancho - anchoCuerpo) / 2,
            top: superiorCuerpo,
            width: anchoCuerpo,
            height: altoCuerpo,
            child: _Cuerpo(estilo: estilo, apertura: tLineal),
          ),

          // Tapa.
          Positioned(
            left: (ancho - anchoTapa) / 2,
            top: superiorTapa,
            width: anchoTapa,
            height: altoTapa,
            child: Transform.translate(
              offset: Offset(
                inclinacionTapa * ancho * 0.28 * t,
                -ancho * 0.62 * t,
              ),
              child: Transform.rotate(
                angle: inclinacionTapa * 0.55 * t,
                child: Opacity(
                  opacity: (1 - math.max(0, tLineal - 0.55) / 0.45)
                      .clamp(0.0, 1.0),
                  child: _Tapa(estilo: estilo, ancho: anchoTapa),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.estilo, required this.apertura});

  final EstiloCaja estilo;
  final double apertura;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (contexto, restricciones) {
        final ancho = restricciones.maxWidth;
        final alto = restricciones.maxHeight;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(ancho * 0.03),
              bottom: Radius.circular(ancho * 0.09),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: estilo.cuerpo,
            ),
            border: Border.all(color: estilo.borde, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: ancho * 0.12,
                offset: Offset(0, ancho * 0.06),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(ancho * 0.03),
              bottom: Radius.circular(ancho * 0.09),
            ),
            child: Stack(
              children: [
                // Cinta vertical.
                Positioned(
                  left: ancho * 0.41,
                  width: ancho * 0.18,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: estilo.cinta,
                      ),
                    ),
                  ),
                ),
                // Brillo diagonal del frente.
                Positioned(
                  left: -ancho * 0.2,
                  top: -alto * 0.3,
                  width: ancho * 0.45,
                  height: alto * 1.6,
                  child: Transform.rotate(
                    angle: 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
                // Borde interior oscuro que se ve al abrir.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: alto * 0.16,
                  child: Opacity(
                    opacity: apertura,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tapa extends StatelessWidget {
  const _Tapa({required this.estilo, required this.ancho});

  final EstiloCaja estilo;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Moño sobre la tapa.
        Positioned(
          left: ancho * 0.22,
          right: ancho * 0.22,
          bottom: ancho * 0.16,
          height: ancho * 0.3,
          child: CustomPaint(painter: _PintorMono(colores: estilo.cinta)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ancho * 0.035),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: estilo.tapa,
              ),
              border: Border.all(color: estilo.borde, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: ancho * 0.05,
                  offset: Offset(0, ancho * 0.02),
                ),
              ],
            ),
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.19,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: estilo.cinta,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dos lazos simetricos y un nudo al centro.
class _PintorMono extends CustomPainter {
  const _PintorMono({required this.colores});

  final List<Color> colores;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height * 0.92);
    final relleno = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colores,
      ).createShader(Offset.zero & size);
    final contorno = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width * 0.015)
      ..color = Colors.black.withValues(alpha: 0.18);

    for (final lado in [-1.0, 1.0]) {
      final lazo = Path()
        ..moveTo(centro.dx, centro.dy)
        ..cubicTo(
          centro.dx + lado * size.width * 0.18,
          -size.height * 0.2,
          centro.dx + lado * size.width * 0.62,
          size.height * 0.05,
          centro.dx + lado * size.width * 0.12,
          centro.dy,
        )
        ..close();
      canvas
        ..drawPath(lazo, relleno)
        ..drawPath(lazo, contorno);
    }

    final nudo = Rect.fromCenter(
      center: centro.translate(0, -size.height * 0.04),
      width: size.width * 0.2,
      height: size.height * 0.34,
    );
    final nudoRedondeado =
        RRect.fromRectAndRadius(nudo, Radius.circular(size.width * 0.06));
    canvas
      ..drawRRect(nudoRedondeado, relleno)
      ..drawRRect(nudoRedondeado, contorno);
  }

  @override
  bool shouldRepaint(_PintorMono anterior) => anterior.colores != colores;
}
