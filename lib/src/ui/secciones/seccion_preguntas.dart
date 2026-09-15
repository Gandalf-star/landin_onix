import 'package:flutter/material.dart';

import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/efectos.dart';
import '../componentes/seccion_pagina.dart';

/// Preguntas frecuentes en acordeon.
class SeccionPreguntas extends StatefulWidget {
  const SeccionPreguntas({super.key});

  @override
  State<SeccionPreguntas> createState() => _SeccionPreguntasState();
}

class _SeccionPreguntasState extends State<SeccionPreguntas> {
  int? _abierta = 0;

  @override
  Widget build(BuildContext context) {
    return SeccionPagina(
      fondo: ColoresOnix.fondo,
      anchoMaximo: 860,
      child: Column(
        children: [
          const EncabezadoSeccion(
            etiqueta: 'Preguntas',
            titulo: 'Lo que todos preguntan',
          ),
          const SizedBox(height: 46),
          for (var i = 0; i < ConfigCampana.preguntas.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Aparicion(
                retraso: Duration(milliseconds: 50 * i),
                child: _Pregunta(
                  pregunta: ConfigCampana.preguntas[i].$1,
                  respuesta: ConfigCampana.preguntas[i].$2,
                  abierta: _abierta == i,
                  alPresionar: () =>
                      setState(() => _abierta = _abierta == i ? null : i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pregunta extends StatelessWidget {
  const _Pregunta({
    required this.pregunta,
    required this.respuesta,
    required this.abierta,
    required this.alPresionar,
  });

  final String pregunta;
  final String respuesta;
  final bool abierta;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: ColoresOnix.blanco,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
        border: Border.all(
          color: abierta ? ColoresOnix.amarilloOnix : ColoresOnix.borde,
          width: abierta ? 1.6 : 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pregunta,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ColoresOnix.texto,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedRotation(
                      turns: abierta ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: abierta
                              ? ColoresOnix.amarilloClaro
                              : ColoresOnix.fondo,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 19,
                          color: ColoresOnix.azulOnix,
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 240),
                  crossFadeState: abierta
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 14, right: 40),
                    child: Text(
                      respuesta,
                      style: const TextStyle(
                        color: ColoresOnix.textoSuave,
                        fontSize: 14.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
