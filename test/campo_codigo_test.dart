import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/ui/registro/campo_codigo.dart';

/// Envuelve el campo y simula la verificacion: al completar se "procesa"
/// (campo bloqueado) y luego se libera como si el codigo fuera incorrecto.
class _Envoltorio extends StatefulWidget {
  const _Envoltorio({required this.controlador, required this.envios});

  final TextEditingController controlador;
  final List<String> envios;

  @override
  State<_Envoltorio> createState() => _EnvoltorioState();
}

class _EnvoltorioState extends State<_Envoltorio> {
  bool procesando = false;

  Future<void> _verificar(String codigo) async {
    widget.envios.add(codigo);
    setState(() => procesando = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (mounted) setState(() => procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: CampoCodigoVerificacion(
              controlador: widget.controlador,
              habilitado: !procesando,
              alCompletar: _verificar,
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('tras un codigo incorrecto se puede borrar y corregir',
      (tester) async {
    final controlador = TextEditingController();
    final envios = <String>[];
    addTearDown(controlador.dispose);

    await tester.pumpWidget(
      _Envoltorio(controlador: controlador, envios: envios),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(envios, ['123456']);

    // Termina la verificacion fallida.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.focusNode!.hasFocus, isTrue);
    expect(controlador.selection, const TextSelection.collapsed(offset: 6));

    // Aunque el cursor quede al inicio, al tocar las casillas vuelve al
    // final y el retroceso borra el ultimo digito.
    controlador.selection = const TextSelection.collapsed(offset: 0);
    expect(controlador.selection, const TextSelection.collapsed(offset: 6));
    await tester.tap(find.byType(CampoCodigoVerificacion));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controlador.text, '12345');
    expect(envios, ['123456'], reason: 'borrar no debe reenviar');

    // El teclado del celular entrega el texto completo ya editado.
    await tester.enterText(find.byType(TextField), '123457');
    await tester.pump();
    expect(controlador.text, '123457');
    expect(envios, ['123456', '123457']);
    await tester.pump(const Duration(milliseconds: 60));
  });
}
