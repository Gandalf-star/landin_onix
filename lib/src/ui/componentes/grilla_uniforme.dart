import 'package:flutter/material.dart';

/// Grilla de tarjetas con columnas del mismo ancho y filas del mismo alto.
///
/// Un `Wrap` deja cada tarjeta con su propio alto y la fila queda dispareja
/// en cuanto un texto ocupa una linea mas. Aqui cada fila se arma con
/// [IntrinsicHeight], asi todas las tarjetas de la fila miden lo mismo, y la
/// ultima fila incompleta se centra para que la grilla quede simetrica.
///
/// Los hijos no deben usar `LayoutBuilder`: no informa su alto intrinseco.
class GrillaUniforme extends StatelessWidget {
  const GrillaUniforme({
    super.key,
    required this.columnas,
    required this.children,
    this.separacion = 20,
  });

  final int columnas;
  final double separacion;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columnas <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: separacion),
            children[i],
          ],
        ],
      );
    }

    final filas = <Widget>[];
    for (var inicio = 0; inicio < children.length; inicio += columnas) {
      final fin = (inicio + columnas).clamp(0, children.length);
      final enFila = children.sublist(inicio, fin);
      final vacias = columnas - enFila.length;

      filas.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Media columna (con su separacion) a cada lado por cada hueco:
              // la fila incompleta queda centrada y sus tarjetas miden lo
              // mismo que las de una fila completa.
              if (vacias > 0) ...[
                Spacer(flex: vacias),
                SizedBox(width: separacion * vacias / 2),
              ],
              for (var i = 0; i < enFila.length; i++) ...[
                if (i > 0) SizedBox(width: separacion),
                Expanded(flex: 2, child: enFila[i]),
              ],
              if (vacias > 0) ...[
                SizedBox(width: separacion * vacias / 2),
                Spacer(flex: vacias),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < filas.length; i++) ...[
          if (i > 0) SizedBox(height: separacion),
          filas[i],
        ],
      ],
    );
  }
}
