import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../nucleo/tema_onix.dart';

/// Campo de codigo de verificacion de 6 digitos.
///
/// Dibuja seis casillas pero por debajo hay un unico campo de texto: asi el
/// pegado desde el SMS y el autocompletado del navegador siguen funcionando.
class CampoCodigoVerificacion extends StatefulWidget {
  const CampoCodigoVerificacion({
    super.key,
    required this.controlador,
    this.largo = 6,
    this.alCompletar,
    this.habilitado = true,
  });

  final TextEditingController controlador;
  final int largo;
  final ValueChanged<String>? alCompletar;
  final bool habilitado;

  @override
  State<CampoCodigoVerificacion> createState() =>
      _CampoCodigoVerificacionState();
}

class _CampoCodigoVerificacionState extends State<CampoCodigoVerificacion> {
  final _foco = FocusNode();

  /// Ultimo texto visto: el controlador tambien avisa cuando solo cambia la
  /// seleccion, y eso no debe volver a disparar la verificacion.
  String _textoAnterior = '';

  @override
  void initState() {
    super.initState();
    _textoAnterior = widget.controlador.text;
    widget.controlador.addListener(_alCambiar);
    _foco.addListener(_alCambiarFoco);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.habilitado) _foco.requestFocus();
    });
  }

  @override
  void didUpdateWidget(CampoCodigoVerificacion anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.controlador != widget.controlador) {
      anterior.controlador.removeListener(_alCambiar);
      widget.controlador.addListener(_alCambiar);
      _textoAnterior = widget.controlador.text;
    }
    // Termino la verificacion (por ejemplo, con un codigo incorrecto):
    // el foco vuelve al campo para poder corregir sin tocar nada.
    if (!anterior.habilitado && widget.habilitado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _foco.requestFocus();
        _cursorAlFinal();
      });
    }
  }

  @override
  void dispose() {
    widget.controlador.removeListener(_alCambiar);
    _foco.removeListener(_alCambiarFoco);
    _foco.dispose();
    super.dispose();
  }

  void _alCambiarFoco() {
    if (!mounted) return;
    if (_foco.hasFocus) _cursorAlFinal();
    setState(() {});
  }

  /// Las casillas se llenan de izquierda a derecha, asi que el cursor del
  /// campo oculto siempre debe quedar al final. Si queda al inicio (pasa al
  /// recuperar el foco), el retroceso no borra nada y el limite de largo
  /// impide escribir: el codigo quedaria imposible de corregir.
  void _cursorAlFinal() {
    final controlador = widget.controlador;
    final fin = controlador.text.length;
    final seleccion = controlador.selection;
    if (seleccion.isCollapsed && seleccion.baseOffset == fin) return;
    controlador.selection = TextSelection.collapsed(offset: fin);
  }

  void _alCambiar() {
    final texto = widget.controlador.text;
    final cambioTexto = texto != _textoAnterior;
    _textoAnterior = texto;
    _cursorAlFinal();
    if (!cambioTexto) return;
    setState(() {});
    if (texto.length == widget.largo) {
      widget.alCompletar?.call(texto);
    }
  }

  void _enfocar() {
    if (!widget.habilitado) return;
    _foco.requestFocus();
    _cursorAlFinal();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (contexto, restricciones) {
        // Las casillas se ajustan al ancho disponible: 48 px en pantallas
        // comodas y mas angostas en celulares chicos, siempre con al menos
        // 6 px entre una y otra para que no se toquen.
        const separacionMinima = 6.0;
        final ancho = ((restricciones.maxWidth -
                    separacionMinima * (widget.largo - 1)) /
                widget.largo)
            .clamp(30.0, 48.0);
        final alto = ancho * 62 / 48;
        return _construir(ancho, alto);
      },
    );
  }

  Widget _construir(double anchoCasilla, double altoCasilla) {
    final texto = widget.controlador.text;

    return Stack(
      children: [
        // Campo real, invisible pero funcional.
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: altoCasilla,
            child: TextField(
              controller: widget.controlador,
              focusNode: _foco,
              // Mientras se verifica el campo queda de solo lectura en vez
              // de deshabilitado: deshabilitarlo le quita el foco y reinicia
              // el cursor, y despues no se podia borrar un digito errado.
              readOnly: !widget.habilitado,
              showCursor: false,
              enableInteractiveSelection: false,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.largo),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onTap: _enfocar,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < widget.largo; i++)
                  _Casilla(
                    digito: i < texto.length ? texto[i] : '',
                    activa: _foco.hasFocus && i == texto.length,
                    ancho: anchoCasilla,
                    alto: altoCasilla,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Casilla extends StatelessWidget {
  const _Casilla({
    required this.digito,
    required this.activa,
    required this.ancho,
    required this.alto,
  });

  final String digito;
  final bool activa;
  final double ancho;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final lleno = digito.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: ancho,
      height: alto,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lleno ? ColoresOnix.amarilloClaro : ColoresOnix.fondo,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(
          color: activa
              ? ColoresOnix.amarilloOnix
              : lleno
                  ? ColoresOnix.amarilloOnix.withValues(alpha: 0.55)
                  : ColoresOnix.borde,
          width: activa ? 2 : 1.4,
        ),
      ),
      child: Text(
        digito,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 25 * ancho / 48,
          fontWeight: FontWeight.w800,
          color: ColoresOnix.azulOnix,
        ),
      ),
    );
  }
}
