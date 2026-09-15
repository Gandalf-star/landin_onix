import 'package:flutter/material.dart';

/// Logotipo oficial de Onix Drive.
///
/// Hay dos versiones del arte: la de trazo azul para fondos claros y la de
/// trazo blanco para fondos oscuros. [sobreFondoOscuro] elige la correcta.
class LogoOnix extends StatelessWidget {
  const LogoOnix({super.key, this.alto = 38, this.sobreFondoOscuro = false});

  final double alto;
  final bool sobreFondoOscuro;

  @override
  Widget build(BuildContext context) {
    final ruta = sobreFondoOscuro
        ? 'assets/images/logo_onix_dark.png'
        : 'assets/images/logo_onix_transparent.png';

    return Image.asset(
      ruta,
      height: alto,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Onix Drive',
    );
  }
}
