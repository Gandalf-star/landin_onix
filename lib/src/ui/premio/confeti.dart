import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';


/// Cada vez que [disparo] cambia, la lluvia arranca de nuevo.
class ConfetiSimetrico extends StatefulWidget {
  const ConfetiSimetrico({super.key, required this.disparo});

  final int disparo;

  static const ruta = 'assets/animaciones/confeti.json';

  @override
  State<ConfetiSimetrico> createState() => _ConfetiSimetricoState();
}

class _ConfetiSimetricoState extends State<ConfetiSimetrico>
    with SingleTickerProviderStateMixin {
  /// Los primeros cuadros del Lottie estan vacios (el confeti todavia esta
  /// por encima del borde): se saltan para que caiga justo al abrir.
  static const _cuadroInicial = 4;

  late final AnimationController _control = AnimationController(vsync: this)
    ..addStatusListener((_) {
      if (mounted) setState(() {});
    });

  LottieComposition? _composicion;

  @override
  void initState() {
    super.initState();
    AssetLottie(ConfetiSimetrico.ruta)
        .load()
        .then((composicion) {
          if (!mounted) return;
          _composicion = composicion;
          _control.duration = composicion.duration;
          if (widget.disparo > 0) _lanzar();
          setState(() {});
        })
        .catchError((Object _) {
          // Sin el asset no hay confeti, pero el premio se muestra igual.
        });
  }

  @override
  void didUpdateWidget(ConfetiSimetrico anterior) {
    super.didUpdateWidget(anterior);
    if (widget.disparo != anterior.disparo) _lanzar();
  }

  void _lanzar() {
    final composicion = _composicion;
    if (composicion == null) return;
    final inicio =
        _cuadroInicial /
        math.max(1, composicion.endFrame - composicion.startFrame);
    _control.forward(from: inicio.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composicion = _composicion;
    if (composicion == null || !_control.isAnimating) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (contexto, restricciones) {
          // El Lottie es cuadrado y el confeti nace en su borde superior: se
          // dibuja en un cuadrado del lado mayor, pegado arriba y centrado,
          // para que cubra todo el ancho sin cortar la parte de donde cae.
          final lado = math.max(
            restricciones.maxWidth,
            restricciones.maxHeight,
          );
          final capa = Lottie(
            composition: composicion,
            controller: _control,
            width: lado,
            height: lado,
            fit: BoxFit.fill,
            frameRate: FrameRate.max,
          );
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minWidth: lado,
              maxWidth: lado,
              minHeight: lado,
              maxHeight: lado,
              child: Stack(
                children: [
                  capa,
                  Transform.flip(flipX: true, child: capa),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
