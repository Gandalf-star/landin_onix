import 'package:flutter/material.dart';

import '../../nucleo/tema_onix.dart';

/// Boton principal de la campana: gradiente amarillo Onix sobre azul.
class BotonDorado extends StatefulWidget {
  const BotonDorado({
    super.key,
    required this.texto,
    required this.alPresionar,
    this.icono,
    this.cargando = false,
    this.expandido = false,
    this.alto = 56,
  });

  final String texto;
  final VoidCallback? alPresionar;
  final IconData? icono;
  final bool cargando;
  final bool expandido;
  final double alto;

  @override
  State<BotonDorado> createState() => _BotonDoradoState();
}

class _BotonDoradoState extends State<BotonDorado> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.alPresionar != null && !widget.cargando;

    final contenido = Row(
      mainAxisSize: widget.expandido ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.cargando)
          const SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: ColoresOnix.azulOnix,
            ),
          )
        else ...[
          if (widget.icono != null) ...[
            Icon(widget.icono, size: 19, color: ColoresOnix.azulOnix),
            const SizedBox(width: 10),
          ],
          // En pantallas muy angostas el texto se achica un poco en vez de
          // cortarse con puntos suspensivos.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.texto,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  color: ColoresOnix.azulOnix,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return MouseRegion(
      cursor: habilitado
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: habilitado ? widget.alPresionar : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: widget.alto,
          width: widget.expandido ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: PuntosQuiebre.esMovilChico(context)
                ? 18
                : (PuntosQuiebre.esMovil(context) ? 22 : 30),
          ),
          transform: Matrix4.translationValues(0, _encima && habilitado ? -2 : 0, 0),
          decoration: BoxDecoration(
            gradient: GradientesOnix.dorado,
            borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
            boxShadow: [
              BoxShadow(
                color: ColoresOnix.amarilloOnix.withValues(
                  alpha: _encima && habilitado ? 0.45 : 0.28,
                ),
                blurRadius: _encima && habilitado ? 30 : 18,
                offset: Offset(0, _encima && habilitado ? 12 : 8),
              ),
            ],
          ),
          child: Opacity(
            opacity: habilitado || widget.cargando ? 1 : 0.55,
            // widthFactor 1: sin `expandido` el boton mide lo que su texto
            // (un Center a secas se estiraba a todo el ancho disponible).
            child: Align(
              widthFactor: widget.expandido ? null : 1,
              child: contenido,
            ),
          ),
        ),
      ),
    );
  }
}

/// Boton secundario translucido, pensado para fondos oscuros.
class BotonFantasma extends StatelessWidget {
  const BotonFantasma({
    super.key,
    required this.texto,
    required this.alPresionar,
    this.icono,
    this.sobreFondoOscuro = true,
    this.alto = 56,
    this.expandido = false,
  });

  final String texto;
  final VoidCallback? alPresionar;
  final IconData? icono;
  final bool sobreFondoOscuro;
  final double alto;
  final bool expandido;

  @override
  Widget build(BuildContext context) {
    final color =
        sobreFondoOscuro ? ColoresOnix.blanco : ColoresOnix.azulOnix;

    return SizedBox(
      height: alto,
      width: expandido ? double.infinity : null,
      child: OutlinedButton(
        onPressed: alPresionar,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: sobreFondoOscuro
              ? ColoresOnix.blanco.withValues(alpha: 0.06)
              : ColoresOnix.blanco,
          side: BorderSide(
            color: sobreFondoOscuro
                ? ColoresOnix.blanco.withValues(alpha: 0.28)
                : ColoresOnix.borde,
            width: 1.4,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: PuntosQuiebre.esMovilChico(context)
                ? 18
                : (PuntosQuiebre.esMovil(context) ? 22 : 30),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  texto,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
