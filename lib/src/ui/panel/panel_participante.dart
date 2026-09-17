import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../datos/controlador_referidos.dart';
import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/botones.dart';
import '../componentes/indicadores.dart';
import '../premio/dialogo_cajas.dart';
import '../premio/ticket_premio.dart';

/// Panel privado del participante: su premio, su avance en tickets, los
/// códigos para invitar y la lista de invitados con el estado de cada uno.
class PanelParticipante extends StatelessWidget {
  const PanelParticipante({super.key});

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final participante = controlador.participante;
    if (participante == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(
        PuntosQuiebre.esMovilChico(context)
            ? 18
            : (PuntosQuiebre.esMovil(context) ? 22 : 26),
      ),
      decoration: BoxDecoration(
        color: ColoresOnix.blanco,
        borderRadius: BorderRadius.circular(MedidasOnix.radioExtra),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Encabezado(participante: participante),
          if (participante.puedeReclamar || controlador.reclamo != null) ...[
            const SizedBox(height: 22),
            _TarjetaPremio(
              participante: participante,
              reclamo: controlador.reclamo,
            ),
          ],
          const SizedBox(height: 22),
          _Avance(participante: participante),
          const SizedBox(height: 26),
          _TarjetaInvitaciones(
            participante: participante,
            invitaciones: controlador.misInvitaciones,
          ),
          const SizedBox(height: 24),
          _ListaInvitados(referidos: controlador.misReferidos),
          if (controlador.modoDemostracion) ...[
            const SizedBox(height: 18),
            _AccionDemostracion(
              cargando: controlador.procesando,
              hayReclamo: controlador.reclamo != null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.participante});

  final Participante participante;

  @override
  Widget build(BuildContext context) {
    // Los botones van solo junto al saludo y el telefono ocupa su propia
    // linea a todo el ancho: en celular ya no se corta con puntos.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '¡Vamos, ${participante.primerNombre}!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 25),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              visualDensity: VisualDensity.compact,
              onPressed: () => ProveedorCampana.accion(context).refrescar(),
              icon: const Icon(Icons.refresh_rounded, size: 19),
              color: ColoresOnix.textoSuave,
            ),
            IconButton(
              tooltip: 'Salir',
              visualDensity: VisualDensity.compact,
              onPressed: () => ProveedorCampana.accion(context).cerrarSesion(),
              icon: const Icon(Icons.logout_rounded, size: 19),
              color: ColoresOnix.textoSuave,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 15,
              color: ColoresOnix.verde,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Número verificado · ${participante.telefonoLegible}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ColoresOnix.textoSuave,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Invitar: el link para compartir con muchos contactos a la vez y, si se
/// quiere, un código individual para una persona.
class _TarjetaInvitaciones extends StatelessWidget {
  const _TarjetaInvitaciones({
    required this.participante,
    required this.invitaciones,
  });

  final Participante participante;
  final List<InvitacionEmitida> invitaciones;

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final individual = controlador.ultimaInvitacion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BloqueEnlace(participante: participante, enlace: controlador.enlace),
        const SizedBox(height: 12),
        if (individual != null) ...[
          _BloqueCodigoActivo(
            participante: participante,
            invitacion: individual,
          ),
          const SizedBox(height: 12),
        ],
        BotonFantasma(
          texto: 'Generar código para invitar',
          icono: Icons.add_circle_outline_rounded,
          sobreFondoOscuro: false,
          expandido: true,
          alPresionar: controlador.procesando
              ? null
              : () => controlador.generarInvitacion(),
        ),
        const SizedBox(height: 6),
        const Text(
          'Un código individual sirve para mandarlo a una sola persona por '
          'otro medio.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ColoresOnix.textoSuave,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (invitaciones.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ListaInvitaciones(invitaciones: invitaciones),
        ],
      ],
    );
  }
}

/// El link de invitacion: se comparte por WhatsApp con muchos contactos y
/// cada persona que lo abre recibe su propio codigo.
///
/// Un link entrega un maximo de codigos; cuando se llena, el servidor
/// devuelve uno nuevo. Por eso el link se renueva solo cada cierto tiempo y
/// despues de cada envio, para no compartir nunca uno que ya se lleno.
class _BloqueEnlace extends StatefulWidget {
  const _BloqueEnlace({required this.participante, required this.enlace});

  final Participante participante;
  final EnlaceInvitacion? enlace;

  @override
  State<_BloqueEnlace> createState() => _BloqueEnlaceState();
}

class _BloqueEnlaceState extends State<_BloqueEnlace> {
  static const _cadaCuanto = Duration(minutes: 2);

  Timer? _renovacion;

  @override
  void initState() {
    super.initState();
    _renovacion = Timer.periodic(_cadaCuanto, (_) => _renovarEnlace());
  }

  @override
  void dispose() {
    _renovacion?.cancel();
    super.dispose();
  }

  void _renovarEnlace() {
    if (!mounted) return;
    unawaited(
      ProveedorCampana.accion(context).actualizarEnlace(silencioso: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final participante = widget.participante;
    final enlace = widget.enlace;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        gradient: GradientesOnix.fondoOscuro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'INVITA A TUS CONTACTOS',
            style: TextStyle(
              color: ColoresOnix.sobreAzulSuave,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Comparte tu link y elige en WhatsApp a todos los que quieras.',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.blanco,
              fontSize: 19,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          const _PasoEnlace(
            numero: '1',
            texto: 'Cada persona que abra el link recibe su propio código, '
                'distinto al de los demás.',
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: ColoresOnix.bordeSobreAzul),
          const SizedBox(height: 14),
          if (enlace == null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Preparando tu link…',
                    style: TextStyle(
                      color: ColoresOnix.sobreAzul,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                _BotonIcono(
                  icono: Icons.refresh_rounded,
                  tooltip: 'Volver a intentar',
                  alPresionar: controlador.actualizarEnlace,
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    controlador.linkDelEnlace(enlace),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ColoresOnix.sobreAzul,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _BotonIcono(
                  icono: Icons.link_rounded,
                  tooltip: 'Copiar link',
                  alPresionar: () => _copiar(
                    context,
                    controlador.linkDelEnlace(enlace),
                    'Link copiado',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${enlace.codigosEntregados} de ${enlace.maxCodigos} códigos '
              'entregados con este link',
              style: const TextStyle(
                color: ColoresOnix.sobreAzulSuave,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 16),
          BotonDorado(
            texto: 'Compartir link por WhatsApp',
            icono: Icons.chat_rounded,
            expandido: true,
            // Se abre en el mismo toque, sin esperar al servidor: si no, el
            // navegador del celular bloquea la ventana de WhatsApp.
            alPresionar: enlace == null
                ? null
                : () {
                    _abrirWhatsApp(
                      controlador.mensajeDelEnlace(participante, enlace),
                    );
                    _renovarEnlace();
                  },
          ),
          const SizedBox(height: 10),
          BotonFantasma(
            texto: 'Copiar mensaje',
            icono: Icons.content_copy_rounded,
            sobreFondoOscuro: true,
            expandido: true,
            alPresionar: enlace == null
                ? null
                : () {
                    _copiar(
                      context,
                      controlador.mensajeDelEnlace(participante, enlace),
                      'Mensaje copiado',
                    );
                    _renovarEnlace();
                  },
          ),
        ],
      ),
    );
  }
}

class _PasoEnlace extends StatelessWidget {
  const _PasoEnlace({required this.numero, required this.texto});

  final String numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: ColoresOnix.amarilloOnix,
            shape: BoxShape.circle,
          ),
          child: Text(
            numero,
            style: const TextStyle(
              color: ColoresOnix.azulOnix,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              color: ColoresOnix.sobreAzul,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Código individual recién generado, listo para copiar o enviar.
class _BloqueCodigoActivo extends StatelessWidget {
  const _BloqueCodigoActivo({
    required this.participante,
    required this.invitacion,
  });

  final Participante participante;
  final InvitacionEmitida invitacion;

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final mensaje = controlador.mensajeDeInvitacion(participante, invitacion);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ColoresOnix.amarilloClaro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
        border: Border.all(
          color: ColoresOnix.amarilloOnix.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'CÓDIGO PARA TU PRÓXIMO INVITADO',
            style: TextStyle(
              color: ColoresOnix.azulOnix,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              invitacion.codigoVisible,
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: ColoresOnix.azulOnix,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sirve para una sola persona. Mándalo por separado: si lo pones en '
            'un mensaje para varios, solo el primero que lo valide suma.',
            style: TextStyle(
              color: ColoresOnix.azulOnix,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _abrirWhatsApp(mensaje),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('Enviar código'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Copiar mensaje',
                onPressed: () => _copiar(context, mensaje, 'Mensaje copiado'),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Abre WhatsApp con el mensaje y sin destinatario: en el celular se eligen
/// uno o varios contactos de la lista.
void _abrirWhatsApp(String mensaje) {
  unawaited(
    launchUrl(
      ControladorReferidos.enlaceWhatsApp(mensaje),
      mode: LaunchMode.externalApplication,
    ),
  );
}

void _copiar(BuildContext context, String texto, String aviso) {
  Clipboard.setData(ClipboardData(text: texto));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(aviso), duration: const Duration(seconds: 2)),
  );
}

class _BotonIcono extends StatelessWidget {
  const _BotonIcono({
    required this.icono,
    required this.tooltip,
    required this.alPresionar,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: ColoresOnix.blanco.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
            border: Border.all(color: ColoresOnix.bordeSobreAzul),
          ),
          child: Icon(icono, size: 18, color: ColoresOnix.blanco),
        ),
      ),
    );
  }
}

/// Lista de codigos emitidos por el participante, con su estado.
class _ListaInvitaciones extends StatelessWidget {
  const _ListaInvitaciones({required this.invitaciones});

  final List<InvitacionEmitida> invitaciones;

  @override
  Widget build(BuildContext context) {
    final visibles = invitaciones.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tus códigos de invitación (${invitaciones.length})',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ColoresOnix.texto,
          ),
        ),
        const SizedBox(height: 12),
        for (final invitacion in visibles) ...[
          _FilaInvitacion(invitacion: invitacion),
          if (invitacion != visibles.last) const SizedBox(height: 8),
        ],
        if (invitaciones.length > visibles.length) ...[
          const SizedBox(height: 10),
          Text(
            'y ${invitaciones.length - visibles.length} más…',
            style: const TextStyle(
              color: ColoresOnix.textoSuave,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _FilaInvitacion extends StatelessWidget {
  const _FilaInvitacion({required this.invitacion});

  final InvitacionEmitida invitacion;

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (invitacion.estado) {
      EstadoInvitacion.usada => (ColoresOnix.verde, Icons.check_circle_rounded),
      EstadoInvitacion.pendiente => (ColoresOnix.ambar, Icons.schedule_rounded),
      EstadoInvitacion.expirada => (ColoresOnix.rojo, Icons.block_rounded),
    };
    final detalle = switch (invitacion.estado) {
      EstadoInvitacion.usada =>
        'Validado · ${invitacion.telefonoInvitado ?? invitacion.nombreInvitado ?? 'invitado verificado'}',
      EstadoInvitacion.pendiente => 'Entregado · esperando que lo valide',
      EstadoInvitacion.expirada => 'Venció sin usarse',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresOnix.fondo,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(color: ColoresOnix.borde),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitacion.codigoVisible,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ColoresOnix.texto,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ColoresOnix.textoSuave,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          EtiquetaEstado(
            texto: invitacion.estado.etiqueta,
            color: color,
            icono: icono,
          ),
        ],
      ),
    );
  }
}


/// Premio: el botón «Reclamar premio», las cajas pendientes de elegir o el
/// ticket ya ganado, según en qué punto esté el reclamo.
class _TarjetaPremio extends StatelessWidget {
  const _TarjetaPremio({required this.participante, required this.reclamo});

  final Participante participante;
  final ReclamoPremio? reclamo;

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final actual = reclamo;

    if (actual != null && actual.cajaAbierta) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tu premio',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ColoresOnix.texto,
                  ),
                ),
              ),
              _EtiquetaReclamo(estado: actual.estado),
            ],
          ),
          const SizedBox(height: 12),
          TicketPremio(
            reclamo: actual,
            nombreGanador: participante.nombre,
            compacto: true,
          ),
          const SizedBox(height: 12),
          BotonFantasma(
            texto: 'Ver mi ticket y las cajas',
            icono: Icons.confirmation_number_rounded,
            sobreFondoOscuro: false,
            alPresionar: () => DialogoCajas.mostrar(context),
          ),
        ],
      );
    }

    final cajasListas = actual != null;
    final soloPrueba = !participante.llegoALaMeta && participante.ganadorPrueba;

    final (titulo, detalle) = cajasListas
        ? (
            'Tus tres cajas te esperan',
            'Ya reclamaste tu premio. Elige una caja para descubrir qué te '
                'llevas.',
          )
        : soloPrueba
            ? (
                'Modo prueba activado',
                'El administrador habilitó tu cuenta para probar el reclamo '
                    'del premio sin tener ${ConfigCampana.metaTickets} tickets.',
              )
            : (
                '¡Llegaste a ${ConfigCampana.metaTickets} tickets!',
                'Reclama tu premio: elige una de tres cajas cerradas y '
                    'llévate lo que esconde.',
              );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: GradientesOnix.fondoOscuro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
        border: Border.all(
          color: ColoresOnix.amarilloOnix.withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  gradient: GradientesOnix.dorado,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.redeem_rounded,
                  color: ColoresOnix.azulOnix,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: ColoresOnix.blanco,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detalle,
                      style: const TextStyle(
                        color: ColoresOnix.sobreAzulSuave,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BotonDorado(
            texto: cajasListas ? 'Elegir mi caja' : 'Reclamar premio',
            icono: cajasListas
                ? Icons.inventory_2_rounded
                : Icons.emoji_events_rounded,
            expandido: true,
            cargando: controlador.procesando,
            alPresionar: () async {
              if (!cajasListas) {
                final ok = await controlador.reclamarPremio();
                if (!ok || !context.mounted) return;
              }
              await DialogoCajas.mostrar(context);
            },
          ),
          if (controlador.mensajeError != null && !cajasListas) ...[
            const SizedBox(height: 10),
            Text(
              controlador.mensajeError!,
              style: const TextStyle(
                color: ColoresOnix.amarilloOnix,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EtiquetaReclamo extends StatelessWidget {
  const _EtiquetaReclamo({required this.estado});

  final EstadoReclamo estado;

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (estado) {
      EstadoReclamo.cajasListas => (ColoresOnix.ambar, Icons.inventory_2_rounded),
      EstadoReclamo.pendiente => (ColoresOnix.ambar, Icons.schedule_rounded),
      EstadoReclamo.verificado => (ColoresOnix.verde, Icons.verified_rounded),
      EstadoReclamo.entregado => (ColoresOnix.verde, Icons.check_circle_rounded),
      EstadoReclamo.rechazado => (ColoresOnix.rojo, Icons.block_rounded),
    };
    return EtiquetaEstado(texto: estado.etiqueta, color: color, icono: icono);
  }
}

class _Avance extends StatelessWidget {
  const _Avance({required this.participante});

  final Participante participante;

  @override
  Widget build(BuildContext context) {
    final faltan = participante.ticketsFaltantes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              '${participante.tickets} de '
              '${ConfigCampana.metaTickets} tickets',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ColoresOnix.texto,
              ),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.redeem_rounded,
                  size: 15,
                  color: ColoresOnix.azulElectrico,
                ),
                SizedBox(width: 5),
                Text(
                  'Meta: abrir una caja',
                  style: TextStyle(
                    color: ColoresOnix.azulElectrico,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        BarraProgresoMeta(
          valor: participante.tickets,
          meta: ConfigCampana.metaTickets,
        ),
        const SizedBox(height: 12),
        Text(
          faltan == 0
              ? '¡Completaste los ${ConfigCampana.metaTickets} tickets! Tu '
                  'premio está listo para reclamar.'
              : 'Te faltan $faltan ${faltan == 1 ? 'ticket' : 'tickets'} '
                  'para reclamar tu premio. Cada invitado que valida su '
                  'código desde su propio celular suma uno.',
          style: const TextStyle(
            color: ColoresOnix.textoSuave,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Dato(
                valor: participante.tickets,
                etiqueta: 'Tickets',
                color: ColoresOnix.verde,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Dato(
                valor: participante.referidosPendientes,
                etiqueta: 'Pendientes',
                color: ColoresOnix.ambar,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Dato(
                valor: faltan,
                etiqueta: 'Faltan',
                color: ColoresOnix.azulElectrico,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  final int valor;
  final String etiqueta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
      ),
      child: Column(
        children: [
          Text(
            '$valor',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            etiqueta,
            style: const TextStyle(
              color: ColoresOnix.textoSuave,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaInvitados extends StatelessWidget {
  const _ListaInvitados({required this.referidos});

  final List<EventoReferido> referidos;

  @override
  Widget build(BuildContext context) {
    if (referidos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ColoresOnix.fondo,
          borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
          border: Border.all(color: ColoresOnix.borde),
        ),
        child: const Column(
          children: [
            Icon(Icons.group_add_rounded, color: ColoresOnix.textoSuave),
            SizedBox(height: 10),
            Text(
              'Todavía no tienes invitados.\nComparte tu link: sumas un '
              'ticket cuando cada contacto valida su código.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ColoresOnix.textoSuave,
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final visibles = referidos.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tus invitados (${referidos.length})',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ColoresOnix.texto,
          ),
        ),
        const SizedBox(height: 12),
        for (final referido in visibles) ...[
          _FilaInvitado(referido: referido),
          if (referido != visibles.last) const SizedBox(height: 8),
        ],
        if (referidos.length > visibles.length) ...[
          const SizedBox(height: 10),
          Text(
            'y ${referidos.length - visibles.length} más…',
            style: const TextStyle(
              color: ColoresOnix.textoSuave,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _FilaInvitado extends StatelessWidget {
  const _FilaInvitado({required this.referido});

  final EventoReferido referido;

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (referido.estado) {
      EstadoReferido.valido => (ColoresOnix.verde, Icons.check_circle_rounded),
      EstadoReferido.pendiente => (ColoresOnix.ambar, Icons.schedule_rounded),
      EstadoReferido.rechazado => (ColoresOnix.rojo, Icons.block_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresOnix.fondo,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(color: ColoresOnix.borde),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referido.nombreInvitado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ColoresOnix.texto,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  referido.telefonoEnmascarado,
                  style: const TextStyle(
                    color: ColoresOnix.textoSuave,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          EtiquetaEstado(
            texto: referido.estado.etiqueta,
            color: color,
            icono: icono,
          ),
        ],
      ),
    );
  }
}

class _AccionDemostracion extends StatelessWidget {
  const _AccionDemostracion({required this.cargando, required this.hayReclamo});

  final bool cargando;
  final bool hayReclamo;

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.accion(context);
    final estiloBoton = FilledButton.styleFrom(
      backgroundColor: ColoresOnix.azulOnix,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresOnix.amarilloClaro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(
          color: ColoresOnix.amarilloOnix.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modo demostración: agrega invitados de prueba para ver cómo '
            'avanza la barra y llegar a las cajas del premio.',
            style: TextStyle(
              color: ColoresOnix.azulOnix,
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed:
                    cargando ? null : () => controlador.simularInvitados(1),
                style: estiloBoton,
                child: const Text('+1'),
              ),
              FilledButton(
                onPressed:
                    cargando ? null : () => controlador.simularInvitados(10),
                style: estiloBoton,
                child: const Text('+10'),
              ),
              if (hayReclamo)
                OutlinedButton(
                  onPressed:
                      cargando ? null : () => controlador.reiniciarPremioDemo(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Reiniciar premio'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
