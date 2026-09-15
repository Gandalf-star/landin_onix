import 'package:flutter/material.dart';

/// Aparicion suave (opacidad + desplazamiento) al montarse el widget.
///
/// Se usa para dar ritmo a las secciones sin sumar dependencias de animacion.
class Aparicion extends StatefulWidget {
  const Aparicion({
    super.key,
    required this.child,
    this.retraso = Duration.zero,
    this.desplazamiento = 26,
    this.duracion = const Duration(milliseconds: 620),
  });

  final Widget child;
  final Duration retraso;
  final double desplazamiento;
  final Duration duracion;

  @override
  State<Aparicion> createState() => _AparicionState();
}

class _AparicionState extends State<Aparicion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: widget.duracion,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.retraso, () {
      if (mounted) _control.forward();
    });
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curva = CurvedAnimation(parent: _control, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curva,
      builder: (contexto, hijo) => Opacity(
        opacity: curva.value,
        child: Transform.translate(
          offset: Offset(0, widget.desplazamiento * (1 - curva.value)),
          child: hijo,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Envuelve un widget y lo eleva levemente cuando el cursor pasa encima.
class ElevacionAlPasar extends StatefulWidget {
  const ElevacionAlPasar({
    super.key,
    required this.constructor,
    this.elevacion = 6,
  });

  /// Recibe `true` mientras el puntero esta sobre el area.
  final Widget Function(BuildContext contexto, bool activo) constructor;
  final double elevacion;

  @override
  State<ElevacionAlPasar> createState() => _ElevacionAlPasarState();
}

class _ElevacionAlPasarState extends State<ElevacionAlPasar> {
  bool _activo = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _activo = true),
      onExit: (_) => setState(() => _activo = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          _activo ? -widget.elevacion : 0,
          0,
        ),
        child: widget.constructor(context, _activo),
      ),
    );
  }
}
