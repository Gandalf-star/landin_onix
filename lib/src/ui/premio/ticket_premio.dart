import 'package:flutter/material.dart';

import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';

/// Ticket ganador: el premio en la parte dorada y el talon azul con el
/// codigo de confirmacion que el equipo Onix pide para entregar el premio.
///
/// - Vertical (por defecto): el talon va abajo. Es la forma del panel y de
///   las pantallas angostas.
/// - [horizontal]: el talon va a la derecha, como un ticket de papel. Ocupa
///   poco alto y deja ver las cajas debajo en pantallas anchas.
///
/// Las dos partes se recortan por separado, cada una con sus medias muescas
/// en el borde que comparten, para no depender de medir donde cae el corte.
class TicketPremio extends StatelessWidget {
  const TicketPremio({
    super.key,
    required this.reclamo,
    required this.nombreGanador,
    this.compacto = false,
    this.horizontal = false,
  });

  final ReclamoPremio reclamo;
  final String nombreGanador;

  /// Version reducida: textos mas chicos y sin las lineas explicativas.
  final bool compacto;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final premio = reclamo.premio;
    if (premio == null) return const SizedBox.shrink();

    final escala = compacto ? 0.78 : 1.0;
    final radioMuesca = 13.0 * escala;

    final dorada = _ParteDorada(
      reclamo: reclamo,
      premio: premio,
      nombreGanador: nombreGanador,
      escala: escala,
      conDetalle: !compacto,
    );
    final talon = _Talon(
      reclamo: reclamo,
      escala: escala,
      conNota: !compacto,
      perforacionVertical: horizontal,
    );

    final contenido = horizontal
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ParteRecortada(
                    recorte: _RecorteParte(
                      radioMuesca: radioMuesca,
                      borde: AxisDirection.right,
                    ),
                    child: dorada,
                  ),
                ),
                SizedBox(
                  width: 270 * escala,
                  child: _ParteRecortada(
                    recorte: _RecorteParte(
                      radioMuesca: radioMuesca,
                      borde: AxisDirection.left,
                    ),
                    child: talon,
                  ),
                ),
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ParteRecortada(
                recorte: _RecorteParte(
                  radioMuesca: radioMuesca,
                  borde: AxisDirection.down,
                ),
                child: dorada,
              ),
              _ParteRecortada(
                recorte: _RecorteParte(
                  radioMuesca: radioMuesca,
                  borde: AxisDirection.up,
                ),
                child: talon,
              ),
            ],
          );

    return contenido;
  }
}

/// Una parte del ticket recortada, con una sombra que sigue exactamente su
/// forma: una sombra rectangular comun se asomaria por las muescas.
class _ParteRecortada extends StatelessWidget {
  const _ParteRecortada({required this.recorte, required this.child});

  final _RecorteParte recorte;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PintorSombra(recorte: recorte),
      child: ClipPath(clipper: recorte, child: child),
    );
  }
}

class _PintorSombra extends CustomPainter {
  const _PintorSombra({required this.recorte});

  final _RecorteParte recorte;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(
      recorte.getClip(size),
      ColoresOnix.azulProfundo,
      14,
      false,
    );
  }

  @override
  bool shouldRepaint(_PintorSombra anterior) =>
      anterior.recorte.borde != recorte.borde ||
      anterior.recorte.radioMuesca != recorte.radioMuesca;
}

class _ParteDorada extends StatelessWidget {
  const _ParteDorada({
    required this.reclamo,
    required this.premio,
    required this.nombreGanador,
    required this.escala,
    required this.conDetalle,
  });

  final ReclamoPremio reclamo;
  final PremioCaja premio;
  final String nombreGanador;
  final double escala;
  final bool conDetalle;

  @override
  Widget build(BuildContext context) {
    final fecha = reclamo.abiertoEn ?? reclamo.creadoEn;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24 * escala,
        20 * escala,
        24 * escala,
        22 * escala,
      ),
      decoration: const BoxDecoration(gradient: GradientesOnix.dorado),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -30 * escala,
            top: -40 * escala,
            child: Icon(
              premio.icono,
              size: 150 * escala,
              color: ColoresOnix.azulOnix.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Pastilla(texto: 'TICKET GANADOR', escala: escala),
                  if (reclamo.esPrueba) ...[
                    SizedBox(width: 8 * escala),
                    _Pastilla(texto: 'PRUEBA', escala: escala, clara: true),
                  ],
                  SizedBox(width: 8 * escala),
                  Expanded(
                    child: Text(
                      ConfigCampana.nombreCampana,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: ColoresOnix.azulOnix.withValues(alpha: 0.75),
                        fontSize: 12 * escala,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16 * escala),
              Row(
                children: [
                  Container(
                    width: 62 * escala,
                    height: 62 * escala,
                    decoration: BoxDecoration(
                      color: ColoresOnix.azulOnix,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ColoresOnix.azulOnix.withValues(alpha: 0.3),
                          blurRadius: 14 * escala,
                          offset: Offset(0, 6 * escala),
                        ),
                      ],
                    ),
                    child: Icon(
                      premio.icono,
                      color: ColoresOnix.amarilloOnix,
                      size: 32 * escala,
                    ),
                  ),
                  SizedBox(width: 16 * escala),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Te ganaste',
                          style: TextStyle(
                            color: ColoresOnix.azulOnix.withValues(alpha: 0.7),
                            fontSize: 12.5 * escala,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          premio.titulo,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: ColoresOnix.azulOnix,
                            fontSize: 25 * escala,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (conDetalle) ...[
                const SizedBox(height: 12),
                Text(
                  premio.detalle,
                  style: TextStyle(
                    color: ColoresOnix.azulOnix.withValues(alpha: 0.78),
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              SizedBox(height: 14 * escala),
              Row(
                children: [
                  Expanded(
                    child: _Dato(
                      etiqueta: 'Ganador',
                      valor: nombreGanador,
                      escala: escala,
                    ),
                  ),
                  SizedBox(width: 12 * escala),
                  _Dato(
                    etiqueta: 'Fecha',
                    valor: _fecha(fecha),
                    escala: escala,
                    alFinal: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
        '${dos(fecha.hour)}:${dos(fecha.minute)}';
  }
}

class _Talon extends StatelessWidget {
  const _Talon({
    required this.reclamo,
    required this.escala,
    required this.conNota,
    required this.perforacionVertical,
  });

  final ReclamoPremio reclamo;
  final double escala;
  final bool conNota;
  final bool perforacionVertical;

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!perforacionVertical) ...[
          SizedBox(
            height: 2 * escala,
            width: double.infinity,
            child: const CustomPaint(
              painter: _PintorPerforacion(vertical: false),
            ),
          ),
          SizedBox(height: 16 * escala),
        ],
        Text(
          'CÓDIGO DE CONFIRMACIÓN',
          style: TextStyle(
            color: ColoresOnix.sobreAzulSuave,
            fontSize: 10.5 * escala,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: 6 * escala),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            reclamo.codigoConfirmacionVisible ?? '',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.amarilloOnix,
              fontSize: 27 * escala,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        SizedBox(height: 10 * escala),
        SizedBox(
          height: 26 * escala,
          width: double.infinity,
          child: CustomPaint(
            painter: _PintorBarras(
              semilla: reclamo.codigoConfirmacion ?? reclamo.id,
            ),
          ),
        ),
        if (conNota) ...[
          const SizedBox(height: 12),
          const Text(
            'Guárdalo: el equipo Onix lo pedirá para validar tu premio y '
            'coordinar la entrega.',
            style: TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ],
    );

    if (!perforacionVertical) {
      return Container(
        color: ColoresOnix.azulOnix,
        padding: EdgeInsets.fromLTRB(24 * escala, 0, 24 * escala, 20 * escala),
        child: contenido,
      );
    }

    return Container(
      color: ColoresOnix.azulOnix,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 2 * escala,
            child: const CustomPaint(
              painter: _PintorPerforacion(vertical: true),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22 * escala,
                20 * escala,
                22 * escala,
                20 * escala,
              ),
              child: Align(alignment: Alignment.centerLeft, child: contenido),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({
    required this.texto,
    required this.escala,
    this.clara = false,
  });

  final String texto;
  final double escala;
  final bool clara;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * escala,
        vertical: 5 * escala,
      ),
      decoration: BoxDecoration(
        color: clara
            ? ColoresOnix.blanco.withValues(alpha: 0.7)
            : ColoresOnix.azulOnix,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: clara ? ColoresOnix.azulOnix : ColoresOnix.amarilloOnix,
          fontSize: 10.5 * escala,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.escala,
    this.alFinal = false,
  });

  final String etiqueta;
  final String valor;
  final double escala;
  final bool alFinal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alFinal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: TextStyle(
            color: ColoresOnix.azulOnix.withValues(alpha: 0.6),
            fontSize: 9.5 * escala,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ColoresOnix.azulOnix,
            fontSize: 13.5 * escala,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Rectangulo redondeado con dos medias muescas en el borde [borde], que es
/// el que toca a la otra parte del ticket. Las esquinas de ese borde quedan
/// rectas y las del lado opuesto, redondeadas.
class _RecorteParte extends CustomClipper<Path> {
  const _RecorteParte({required this.radioMuesca, required this.borde});

  final double radioMuesca;
  final AxisDirection borde;

  @override
  Path getClip(Size size) {
    const redondo = Radius.circular(22);
    final w = size.width;
    final h = size.height;

    final (arribaIzq, arribaDer, abajoIzq, abajoDer) = switch (borde) {
      AxisDirection.down => (redondo, redondo, Radius.zero, Radius.zero),
      AxisDirection.up => (Radius.zero, Radius.zero, redondo, redondo),
      AxisDirection.right => (redondo, Radius.zero, redondo, Radius.zero),
      AxisDirection.left => (Radius.zero, redondo, Radius.zero, redondo),
    };
    final (centroA, centroB) = switch (borde) {
      AxisDirection.down => (Offset(0, h), Offset(w, h)),
      AxisDirection.up => (Offset.zero, Offset(w, 0)),
      AxisDirection.right => (Offset(w, 0), Offset(w, h)),
      AxisDirection.left => (Offset.zero, Offset(0, h)),
    };

    final rectangulo = RRect.fromLTRBAndCorners(
      0,
      0,
      w,
      h,
      topLeft: arribaIzq,
      topRight: arribaDer,
      bottomLeft: abajoIzq,
      bottomRight: abajoDer,
    );
    final muescas = Path()
      ..addOval(Rect.fromCircle(center: centroA, radius: radioMuesca))
      ..addOval(Rect.fromCircle(center: centroB, radius: radioMuesca));
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(rectangulo),
      muescas,
    );
  }

  @override
  bool shouldReclip(_RecorteParte anterior) =>
      anterior.radioMuesca != radioMuesca || anterior.borde != borde;
}

/// Linea punteada de la perforacion del talon.
class _PintorPerforacion extends CustomPainter {
  const _PintorPerforacion({required this.vertical});

  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final grosor = vertical ? size.width : size.height;
    final largoTotal = vertical ? size.height : size.width;
    final pintura = Paint()
      ..color = ColoresOnix.amarilloOnix.withValues(alpha: 0.45)
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round;
    const largo = 7.0;
    const hueco = 6.0;
    for (var p = 16.0; p < largoTotal - 16; p += largo + hueco) {
      final desde = vertical ? Offset(grosor / 2, p) : Offset(p, grosor / 2);
      final hasta = vertical
          ? Offset(grosor / 2, p + largo)
          : Offset(p + largo, grosor / 2);
      canvas.drawLine(desde, hasta, pintura);
    }
  }

  @override
  bool shouldRepaint(_PintorPerforacion anterior) =>
      anterior.vertical != vertical;
}

/// Codigo de barras decorativo derivado del codigo de confirmacion: cada
/// ticket tiene el suyo.
class _PintorBarras extends CustomPainter {
  const _PintorBarras({required this.semilla});

  final String semilla;

  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = ColoresOnix.sobreAzul.withValues(alpha: 0.85);
    final unidades = semilla.codeUnits;
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final valor = unidades[i % unidades.length] + i * 7;
      final grosor = 1.0 + (valor % 3);
      final hueco = 1.5 + (valor % 4) * 0.8;
      canvas.drawRect(Rect.fromLTWH(x, 0, grosor, size.height), pintura);
      x += grosor + hueco;
      i++;
    }
  }

  @override
  bool shouldRepaint(_PintorBarras anterior) => anterior.semilla != semilla;
}
