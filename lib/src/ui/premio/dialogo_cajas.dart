import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../datos/modelos.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/botones.dart';
import 'caja_regalo.dart';
import 'confeti.dart';
import 'ticket_premio.dart';

/// Abre la escena de las tres cajas sobre la landing.
///
/// Si el reclamo ya tiene la caja abierta, la escena arranca directamente
/// en el ticket (sin volver a lanzar el confeti).
abstract final class DialogoCajas {
  static Future<void> mostrar(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Elige tu caja',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (contexto, animacion, secundaria) => const EscenaCajas(),
      transitionBuilder: (contexto, animacion, secundaria, hijo) {
        final curva = CurvedAnimation(
          parent: animacion,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curva,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curva),
            child: hijo,
          ),
        );
      },
    );
  }
}

enum _Fase {
  /// Tres cajas cerradas esperando la eleccion.
  eligiendo,

  /// La caja elegida tiembla mientras el servidor la abre.
  abriendo,

  /// Se abre la tapa, cae el confeti y sube el ticket.
  revelando,

  /// Ticket a la vista y las otras dos cajas abiertas.
  revelado,
}

/// Escena del premio: tres cajas cerradas (azul, amarilla, azul), una sola
/// se puede abrir, y al abrirla aparece el ticket ganador y lo que habia en
/// las otras dos.
///
/// La escena nunca sabe de antemano que hay en cada caja: la distribucion
/// llega del servidor recien en la respuesta de [ControladorReferidos.abrirCaja].
class EscenaCajas extends StatefulWidget {
  const EscenaCajas({super.key});

  @override
  State<EscenaCajas> createState() => _EscenaCajasState();
}

class _EscenaCajasState extends State<EscenaCajas>
    with TickerProviderStateMixin {
  /// Simetricas: azul a los lados, amarilla al centro.
  static const _estilos = [EstiloCaja.roja, EstiloCaja.amarilla, EstiloCaja.roja];

  /// Las tapas de los lados salen hacia afuera y la del centro hacia arriba.
  static const _inclinaciones = [-1.0, 0.0, 1.0];

  /// Suspenso minimo antes de abrir, aunque el servidor responda al tiro.
  static const _suspenso = Duration(milliseconds: 1100);

  late final AnimationController _flotar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();
  late final AnimationController _sacudir = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );
  late final AnimationController _apertura = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _ticket = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _otras = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  late final AnimationController _rayos = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  final _temporizadores = <Timer>[];

  _Fase _fase = _Fase.eligiendo;
  int? _elegida;
  int? _encima;
  int _disparoConfeti = 0;
  bool _codigoCopiado = false;

  @override
  void initState() {
    super.initState();
    final reclamo = ProveedorCampana.accion(context).reclamo;
    if (reclamo != null && reclamo.cajaAbierta) {
      _fase = _Fase.revelado;
      _elegida = reclamo.cajaElegida;
      _apertura.value = 1;
      _ticket.value = 1;
      _otras.value = 1;
      _flotar.stop();
    }
  }

  @override
  void dispose() {
    for (final temporizador in _temporizadores) {
      temporizador.cancel();
    }
    _flotar.dispose();
    _sacudir.dispose();
    _apertura.dispose();
    _ticket.dispose();
    _otras.dispose();
    _rayos.dispose();
    super.dispose();
  }

  void _despues(Duration espera, VoidCallback accion) {
    _temporizadores.add(Timer(espera, () {
      if (mounted) accion();
    }));
  }

  Future<void> _elegir(int caja) async {
    if (_fase != _Fase.eligiendo) return;
    unawaited(HapticFeedback.mediumImpact());
    final controlador = ProveedorCampana.accion(context);

    setState(() {
      _fase = _Fase.abriendo;
      _elegida = caja;
      _encima = null;
    });
    unawaited(_sacudir.repeat(reverse: true));

    final respuestas = await Future.wait<Object?>([
      controlador.abrirCaja(caja),
      Future<void>.delayed(_suspenso),
    ]);
    if (!mounted) return;

    _sacudir
      ..stop()
      ..value = 0;
    final reclamo = respuestas.first as ReclamoPremio?;

    if (reclamo == null || !reclamo.cajaAbierta) {
      setState(() {
        _fase = _Fase.eligiendo;
        _elegida = null;
      });
      return;
    }

    // Si justo antes se habia abierto otra caja (dos clics en dos pestañas),
    // manda la que registro el servidor.
    setState(() {
      _elegida = reclamo.cajaElegida;
      _fase = _Fase.revelando;
      _disparoConfeti++;
    });
    _flotar.stop();
    unawaited(HapticFeedback.heavyImpact());

    unawaited(_apertura.forward());
    _despues(const Duration(milliseconds: 420), () => _ticket.forward());
    _despues(const Duration(milliseconds: 1500), () => _otras.forward());
    _despues(const Duration(milliseconds: 2400), () {
      setState(() => _fase = _Fase.revelado);
    });
  }

  Future<void> _copiarCodigo(String codigo) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    if (!mounted) return;
    setState(() => _codigoCopiado = true);
    _despues(const Duration(seconds: 2), () {
      setState(() => _codigoCopiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final reclamo = controlador.reclamo;
    final participante = controlador.participante;
    final abierta = _fase == _Fase.revelando || _fase == _Fase.revelado;
    final puedeCerrar = _fase == _Fase.eligiendo || _fase == _Fase.revelado;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: GradientesOnix.fondoOscuro),
        child: Stack(
          children: [
            const Positioned.fill(child: _FondoEscena()),
            SafeArea(
              child: LayoutBuilder(
                builder: (contexto, restricciones) {
                  final ancho = restricciones.maxWidth;
                  final alto = restricciones.maxHeight;
                  // Cada caja ocupa su ancho, mas la etiqueta (1,25 veces)
                  // y la separacion: tres entran holgadas en ancho / 4,8.
                  final porAncho = (ancho - 40) / 4.8;
                  final grande = math.min(
                    math.min(porAncho, alto * 0.25),
                    200.0,
                  );
                  final chica = math.min(porAncho, 112.0);
                  // En pantallas anchas el ticket va acostado (talón a la
                  // derecha) para que las cajas reveladas quepan debajo; en
                  // las angostas y bajas se usa la versión compacta.
                  final horizontal = ancho >= 820;
                  final compacto = !horizontal && alto < 980;

                  return Column(
                    children: [
                      _BarraSuperior(
                        puedeCerrar: puedeCerrar,
                        esPrueba: reclamo?.esPrueba ?? false,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(0, alto - 100),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Encabezado(
                                  abierta: abierta,
                                  abriendo: _fase == _Fase.abriendo,
                                ),
                                if (reclamo != null && reclamo.cajaAbierta)
                                  _construirTicket(
                                    reclamo,
                                    participante?.nombre ?? '',
                                    horizontal: horizontal,
                                    compacto: compacto,
                                  ),
                                SizedBox(height: abierta ? 26 : 44),
                                if (reclamo == null)
                                  const _SinReclamo()
                                else
                                  _construirCajas(reclamo, grande, chica),
                                if (_fase == _Fase.eligiendo &&
                                    controlador.mensajeError != null) ...[
                                  const SizedBox(height: 24),
                                  _AvisoError(
                                    mensaje: controlador.mensajeError!,
                                  ),
                                ],
                                if (reclamo != null &&
                                    reclamo.cajaAbierta) ...[
                                  const SizedBox(height: 30),
                                  FadeTransition(
                                    opacity: _otras,
                                    child: _AccionesFinales(
                                      reclamo: reclamo,
                                      telefono:
                                          participante?.telefonoLegible ?? '',
                                      codigoCopiado: _codigoCopiado,
                                      alCopiar: _copiarCodigo,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // El confeti va por encima de todo y sin capturar toques.
            Positioned.fill(
              child: ConfetiSimetrico(disparo: _disparoConfeti),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirTicket(
    ReclamoPremio reclamo,
    String nombre, {
    required bool horizontal,
    required bool compacto,
  }) {
    return AnimatedBuilder(
      animation: _ticket,
      builder: (contexto, hijo) {
        final t = _ticket.value;
        final altura = Curves.easeOutCubic.transform(t);
        final escala = 0.55 + 0.45 * Curves.elasticOut.transform(t);
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: altura,
            child: Opacity(
              opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
              child: Transform.translate(
                offset: Offset(0, 90 * (1 - altura)),
                child: Transform.scale(scale: escala, child: hijo),
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 26),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: horizontal ? 780 : 440),
          child: TicketPremio(
            reclamo: reclamo,
            nombreGanador: nombre,
            horizontal: horizontal,
            compacto: compacto,
          ),
        ),
      ),
    );
  }

  Widget _construirCajas(ReclamoPremio reclamo, double grande, double chica) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _flotar,
        _sacudir,
        _apertura,
        _ticket,
        _otras,
        _rayos,
      ]),
      builder: (contexto, _) {
        final encoge = Curves.easeInOutCubic.transform(_ticket.value);
        final tamano = grande + (chica - grande) * encoge;
        final separacion = tamano * 0.22;

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: separacion / 2),
                  child: _construirCaja(reclamo, i, tamano),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _construirCaja(ReclamoPremio reclamo, int indice, double tamano) {
    final elegida = _elegida == indice;
    final distribucion = reclamo.distribucion;
    final premioAqui =
        distribucion.length == 3 ? distribucion[indice] : null;
    final eligiendo = _fase == _Fase.eligiendo;

    final apertura = elegida ? _apertura.value : _otras.value;
    final flotacion = eligiendo
        ? math.sin((_flotar.value + indice / 3) * 2 * math.pi) * tamano * 0.035
        : 0.0;
    final sacudida = _fase == _Fase.abriendo && elegida
        ? (_sacudir.value - 0.5) * 0.14
        : 0.0;
    final opacidad = switch (_fase) {
      _Fase.abriendo when !elegida => 0.4,
      _Fase.revelando || _Fase.revelado when !elegida =>
        0.55 + 0.45 * _otras.value,
      _ => 1.0,
    };
    final escalaEncima = _encima == indice && eligiendo ? 1.07 : 1.0;

    final caja = CajaRegalo(
      tamano: tamano,
      estilo: _estilos[indice],
      apertura: apertura,
      brillo: elegida ? _apertura.value : _otras.value * 0.3,
      inclinacionTapa: _inclinaciones[indice],
      contenido: premioAqui == null
          ? null
          : _PremioAsomando(
              premio: premioAqui,
              tamano: tamano,
              destacado: elegida,
            ),
    );

    return MouseRegion(
      cursor: eligiendo ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (eligiendo) setState(() => _encima = indice);
      },
      onExit: (_) {
        if (_encima == indice) setState(() => _encima = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: eligiendo ? () => _elegir(indice) : null,
        child: Semantics(
          button: eligiendo,
          label: 'Caja ${indice + 1}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (elegida && _apertura.value > 0)
                    Positioned(
                      left: -tamano * 0.55,
                      right: -tamano * 0.55,
                      top: -tamano * 0.5,
                      bottom: -tamano * 0.25,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _PintorRayos(
                            giro: _rayos.value,
                            intensidad: _apertura.value,
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(0, flotacion),
                    child: Transform.rotate(
                      angle: sacudida,
                      child: AnimatedScale(
                        scale: escalaEncima,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: Opacity(opacity: opacidad, child: caja),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: tamano * 0.12),
              SizedBox(
                width: tamano * 1.25,
                child: _EtiquetaCaja(
                  indice: indice,
                  elegida: elegida,
                  premio: premioAqui,
                  revelado: _otras.value,
                  abierta: _fase == _Fase.revelando || _fase == _Fase.revelado,
                  compacta: tamano < 100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FondoEscena extends StatelessWidget {
  const _FondoEscena();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.25),
          radius: 0.85,
          colors: [Color(0x8C14338F), Color(0x0014338F)],
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({required this.puedeCerrar, required this.esPrueba});

  final bool puedeCerrar;
  final bool esPrueba;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          const Icon(
            Icons.redeem_rounded,
            color: ColoresOnix.amarilloOnix,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Flexible(
            fit: FlexFit.tight,
            child: Text(
              'Reto 50 Onix · Tu premio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                color: ColoresOnix.sobreAzul,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (esPrueba) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ColoresOnix.ambar.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: ColoresOnix.ambar.withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                'MODO PRUEBA',
                style: TextStyle(
                  color: ColoresOnix.amarilloOnix,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Cerrar',
            onPressed: puedeCerrar ? () => Navigator.of(context).pop() : null,
            icon: const Icon(Icons.close_rounded),
            color: ColoresOnix.sobreAzul,
            disabledColor: ColoresOnix.sobreAzulSuave.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.abierta, required this.abriendo});

  final bool abierta;
  final bool abriendo;

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final (titulo, bajada) = abierta
        ? (
            '¡Felicitaciones!',
            'Este es tu ticket ganador. Abajo puedes ver qué había en las '
                'otras dos cajas.',
          )
        : (
            'Elige tu caja',
            abriendo
                ? 'Abriendo tu caja…'
                : 'Hay un premio distinto escondido en cada caja y solo puedes '
                    'abrir una. Tu elección es definitiva.',
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      child: Column(
        key: ValueKey(abierta),
        children: [
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: ColoresOnix.blanco,
                  fontSize: esMovil ? 34 : 48,
                ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                bajada,
                key: ValueKey(bajada),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: abriendo
                      ? ColoresOnix.amarilloOnix
                      : ColoresOnix.sobreAzulSuave,
                  fontSize: esMovil ? 15 : 17,
                  height: 1.5,
                  fontWeight: abriendo ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que sube desde el interior de cada caja al abrirse.
class _PremioAsomando extends StatelessWidget {
  const _PremioAsomando({
    required this.premio,
    required this.tamano,
    required this.destacado,
  });

  final PremioCaja premio;
  final double tamano;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final diametro = tamano * 0.42;
    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: destacado ? GradientesOnix.dorado : null,
        color: destacado ? null : ColoresOnix.azulSuave,
        border: Border.all(
          color: destacado
              ? ColoresOnix.blanco.withValues(alpha: 0.8)
              : ColoresOnix.amarilloOnix.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ColoresOnix.amarilloOnix
                .withValues(alpha: destacado ? 0.55 : 0.2),
            blurRadius: tamano * 0.18,
          ),
        ],
      ),
      child: Icon(
        premio.icono,
        size: diametro * 0.52,
        color: destacado ? ColoresOnix.azulOnix : ColoresOnix.amarilloOnix,
      ),
    );
  }
}

class _EtiquetaCaja extends StatelessWidget {
  const _EtiquetaCaja({
    required this.indice,
    required this.elegida,
    required this.premio,
    required this.revelado,
    required this.abierta,
    required this.compacta,
  });

  final int indice;
  final bool elegida;
  final PremioCaja? premio;
  final double revelado;
  final bool abierta;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    if (!abierta || premio == null) {
      return Text(
        'Caja ${indice + 1}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Manrope',
          color: ColoresOnix.sobreAzulSuave,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      );
    }

    final tamanoTexto = compacta ? 11.5 : 13.0;

    if (elegida) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: GradientesOnix.dorado,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'TU CAJA',
              style: TextStyle(
                color: ColoresOnix.azulOnix,
                fontSize: tamanoTexto - 1.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            premio!.titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.amarilloOnix,
              fontSize: tamanoTexto,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Opacity(
      opacity: revelado.clamp(0.0, 1.0),
      child: Column(
        children: [
          Text(
            'Aquí había',
            style: TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: tamanoTexto - 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            premio!.titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.sobreAzul,
              fontSize: tamanoTexto,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccionesFinales extends StatelessWidget {
  const _AccionesFinales({
    required this.reclamo,
    required this.telefono,
    required this.codigoCopiado,
    required this.alCopiar,
  });

  final ReclamoPremio reclamo;
  final String telefono;
  final bool codigoCopiado;
  final ValueChanged<String> alCopiar;

  @override
  Widget build(BuildContext context) {
    final codigo = reclamo.codigoConfirmacionVisible ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        children: [
          Text(
            reclamo.esPrueba
                ? 'Ticket de prueba habilitado por el administrador: sirve para '
                    'revisar el recorrido y no se entrega premio.'
                : 'El equipo Onix verificará tu código y te contactará al '
                    '$telefono para coordinar la entrega.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          // Los dos botones siempre con el mismo ancho: lado a lado si caben
          // y uno sobre otro en celulares. Antes el dorado ocupaba toda la
          // linea y «Listo» quedaba chico debajo.
          LayoutBuilder(
            builder: (contexto, restricciones) {
              final copiar = BotonDorado(
                texto: codigoCopiado ? 'Código copiado' : 'Copiar código',
                icono: codigoCopiado ? Icons.check_rounded : Icons.copy_rounded,
                expandido: true,
                alPresionar: () => alCopiar(codigo),
              );
              final listo = BotonFantasma(
                texto: 'Listo',
                icono: Icons.done_all_rounded,
                expandido: true,
                alPresionar: () => Navigator.of(context).pop(),
              );
              return restricciones.maxWidth >= 360
                  ? Row(
                      children: [
                        Expanded(child: copiar),
                        const SizedBox(width: 12),
                        Expanded(child: listo),
                      ],
                    )
                  : Column(
                      children: [copiar, const SizedBox(height: 12), listo],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ColoresOnix.rojo.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
          border: Border.all(color: ColoresOnix.rojo.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: ColoresOnix.rojo),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: ColoresOnix.sobreAzul,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinReclamo extends StatelessWidget {
  const _SinReclamo();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Todavía no hay un premio reclamado en esta cuenta.',
      style: TextStyle(color: ColoresOnix.sobreAzulSuave, fontSize: 15),
    );
  }
}

/// Destellos que giran detras de la caja abierta.
class _PintorRayos extends CustomPainter {
  const _PintorRayos({required this.giro, required this.intensidad});

  final double giro;
  final double intensidad;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height * 0.42);
    final radio = size.shortestSide * 0.62;
    const rayos = 14;
    // El degradado se crea centrado en el origen porque se dibuja despues
    // de trasladar el lienzo al centro de la caja.
    final pintura = Paint()
      ..shader = RadialGradient(
        colors: [
          ColoresOnix.amarilloOnix.withValues(alpha: 0.34 * intensidad),
          ColoresOnix.amarilloOnix.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radio));

    canvas
      ..save()
      ..translate(centro.dx, centro.dy)
      ..rotate(giro * 2 * math.pi);
    for (var i = 0; i < rayos; i++) {
      final angulo = i * 2 * math.pi / rayos;
      const abertura = math.pi / rayos * 0.55;
      final rayo = Path()
        ..moveTo(0, 0)
        ..lineTo(
          math.cos(angulo - abertura) * radio,
          math.sin(angulo - abertura) * radio,
        )
        ..lineTo(
          math.cos(angulo + abertura) * radio,
          math.sin(angulo + abertura) * radio,
        )
        ..close();
      canvas.drawPath(rayo, pintura);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorRayos anterior) =>
      anterior.giro != giro || anterior.intensidad != intensidad;
}
