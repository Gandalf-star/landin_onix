import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../nucleo/arranque.dart';
import '../../nucleo/tema_onix.dart';

/// Etiqueta flotante que dice de donde salen los datos de la landing.
///
/// Cuando Supabase responde, el distintivo solo aparece en depuracion: en
/// produccion no tiene por que verse. Cuando hubo que caer a los datos de
/// demostracion se muestra siempre y se puede desplegar para leer el motivo,
/// porque una landing con todos los contadores en cero y sin explicacion es
/// mucho peor que un aviso discreto.
class DistintivoOrigenDatos extends StatefulWidget {
  const DistintivoOrigenDatos({super.key, required this.arranque});

  final ResultadoArranque arranque;

  @override
  State<DistintivoOrigenDatos> createState() => _DistintivoOrigenDatosState();
}

class _DistintivoOrigenDatosState extends State<DistintivoOrigenDatos> {
  bool _desplegado = false;
  bool _oculto = false;

  @override
  Widget build(BuildContext context) {
    final conectado = widget.arranque.usaSupabase;
    if (_oculto || (conectado && !kDebugMode)) {
      return const SizedBox.shrink();
    }

    final color = conectado ? ColoresOnix.verde : ColoresOnix.amarilloOnix;
    final aviso = widget.arranque.aviso;

    return Positioned(
      left: 16,
      bottom: 16,
      child: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          // Nunca mas ancho que la pantalla menos los margenes de 16 px.
          constraints: BoxConstraints(
            maxWidth: math.min(
              _desplegado ? 380 : 260,
              MediaQuery.sizeOf(context).width - 32,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: ColoresOnix.azulOnix.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
            border: Border.all(color: color.withValues(alpha: 0.45)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      conectado
                          ? 'Datos en vivo · Supabase'
                          : 'Datos de demostración',
                      style: const TextStyle(
                        color: ColoresOnix.sobreAzul,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (aviso != null)
                    _BotonIcono(
                      icono: _desplegado
                          ? Icons.expand_more_rounded
                          : Icons.info_outline_rounded,
                      etiqueta: _desplegado ? 'Ocultar detalle' : 'Ver por qué',
                      alTocar: () => setState(() => _desplegado = !_desplegado),
                    ),
                  _BotonIcono(
                    icono: Icons.close_rounded,
                    etiqueta: 'Cerrar aviso',
                    alTocar: () => setState(() => _oculto = true),
                  ),
                ],
              ),
              if (_desplegado && aviso != null) ...[
                const SizedBox(height: 8),
                Text(
                  aviso,
                  style: const TextStyle(
                    color: ColoresOnix.sobreAzulSuave,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonIcono extends StatelessWidget {
  const _BotonIcono({
    required this.icono,
    required this.etiqueta,
    required this.alTocar,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: etiqueta,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icono, size: 16, color: ColoresOnix.sobreAzulSuave),
        ),
      ),
    );
  }
}
