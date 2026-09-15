import 'package:flutter/material.dart';

import '../nucleo/config_campana.dart';
import '../utiles/codigo_referido.dart';
import '../utiles/telefono.dart';

/// Estado de un referido dentro del embudo.
///
/// - [pendiente] el invitado se registro pero aun no verifico su telefono.
/// - [valido]    verificado y con su dispositivo anclado: suma un ticket.
/// - [rechazado] descartado por el motor anti-fraude o por revision manual.
enum EstadoReferido {
  pendiente,
  valido,
  rechazado;

  String get etiqueta => switch (this) {
        EstadoReferido.pendiente => 'Pendiente',
        EstadoReferido.valido => 'Válido',
        EstadoReferido.rechazado => 'Rechazado',
      };
}

/// Un participante de la campana. La identidad es el telefono en E.164,
/// verificado una sola vez al crear la cuenta; para volver a entrar se usa
/// [nombreUsuario] y contrasena.
@immutable
class Participante {
  const Participante({
    required this.id,
    required this.nombre,
    required this.telefonoE164,
    required this.creadoEn,
    required this.telefonoVerificado,
    this.nombreUsuario,
    this.codigoInvitador,
    this.referidosValidos = 0,
    this.referidosPendientes = 0,
    this.ganadorPrueba = false,
  });

  final String id;
  final String nombre;
  final String telefonoE164;

  /// Nombre de usuario con el que inicia sesion, ya normalizado en
  /// minusculas. Puede faltar en participantes creados antes de que
  /// existieran las cuentas.
  final String? nombreUsuario;

  /// Codigo de invitacion de un solo uso que se canjeo al registrarse. Se
  /// fija UNA sola vez y despues es inmutable: ahi vive la garantia de "un
  /// codigo por persona". No es un codigo propio para compartir: para eso
  /// existen las invitaciones que genera cada participante (ver
  /// [InvitacionEmitida]).
  final String? codigoInvitador;

  final DateTime creadoEn;
  final bool telefonoVerificado;
  final int referidosValidos;
  final int referidosPendientes;

  /// Cuenta habilitada desde el panel admin para probar el reclamo del
  /// premio sin haber llegado a la meta.
  final bool ganadorPrueba;

  String get telefonoLegible => UtilesTelefono.formatoLegible(telefonoE164);

  String get primerNombre => nombre.trim().split(RegExp(r'\s+')).first;

  /// Un ticket por cada invitado verificado con su dispositivo anclado.
  int get tickets => referidosValidos * ConfigCampana.ticketsPorReferido;

  double get avanceMeta =>
      (tickets / ConfigCampana.metaTickets).clamp(0.0, 1.0);

  int get ticketsFaltantes =>
      (ConfigCampana.metaTickets - tickets).clamp(0, ConfigCampana.metaTickets);

  bool get llegoALaMeta => tickets >= ConfigCampana.metaTickets;

  /// Puede pulsar «Reclamar premio»: llego a la meta o el administrador lo
  /// habilito para probar.
  bool get puedeReclamar => llegoALaMeta || ganadorPrueba;

  Participante copiarCon({
    String? nombre,
    bool? telefonoVerificado,
    int? referidosValidos,
    int? referidosPendientes,
    bool? ganadorPrueba,
  }) {
    return Participante(
      id: id,
      nombre: nombre ?? this.nombre,
      telefonoE164: telefonoE164,
      nombreUsuario: nombreUsuario,
      codigoInvitador: codigoInvitador,
      creadoEn: creadoEn,
      telefonoVerificado: telefonoVerificado ?? this.telefonoVerificado,
      referidosValidos: referidosValidos ?? this.referidosValidos,
      referidosPendientes: referidosPendientes ?? this.referidosPendientes,
      ganadorPrueba: ganadorPrueba ?? this.ganadorPrueba,
    );
  }
}

/// Una invitacion concreta: quien invito a quien y en que estado quedo.
@immutable
class EventoReferido {
  const EventoReferido({
    required this.id,
    required this.nombreInvitado,
    required this.telefonoInvitado,
    required this.estado,
    required this.creadoEn,
    this.motivoRechazo,
  });

  final String id;
  final String nombreInvitado;
  final String telefonoInvitado;
  final EstadoReferido estado;
  final DateTime creadoEn;
  final String? motivoRechazo;

  String get telefonoEnmascarado =>
      UtilesTelefono.enmascarar(telefonoInvitado);

  /// Un referido valido solo cuenta para premios despues de la ventana de
  /// maduracion, que da tiempo a revertir fraude detectado tarde.
  bool get estaMaduro =>
      DateTime.now().difference(creadoEn).inHours >=
      ConfigCampana.horasMaduracion;
}

/// Estado de un codigo de invitacion de un solo uso.
///
/// - [pendiente] se genero y todavia no lo canjea nadie.
/// - [usada]     ya lo canjeo la persona a la que se le compartio.
/// - [expirada]  nadie lo canjeo antes de vencer el plazo.
enum EstadoInvitacion {
  pendiente,
  usada,
  expirada;

  String get etiqueta => switch (this) {
        EstadoInvitacion.pendiente => 'Pendiente',
        EstadoInvitacion.usada => 'Usada',
        EstadoInvitacion.expirada => 'Expirada',
      };
}

/// Un codigo de invitacion de un solo uso, generado para compartir con UNA
/// persona concreta por WhatsApp.
///
/// A diferencia de un codigo personal fijo, este codigo solo sirve para que
/// una unica persona se registre: en cuanto alguien lo canjea (o vence el
/// plazo) deja de servir, y para invitar a alguien mas hay que generar otro.
@immutable
class InvitacionEmitida {
  const InvitacionEmitida({
    required this.id,
    required this.codigo,
    required this.creadoEn,
    required this.expiraEn,
    this.usadaEn,
    this.nombreInvitado,
  });

  final String id;

  /// Codigo normalizado (sin prefijo ni guiones). Se muestra con
  /// [codigoVisible].
  final String codigo;

  final DateTime creadoEn;
  final DateTime expiraEn;

  /// Momento en que alguien lo canjeo, o `null` si sigue pendiente.
  final DateTime? usadaEn;

  /// Nombre de quien lo canjeo. Solo se llena una vez que [usadaEn] no es
  /// nulo.
  final String? nombreInvitado;

  String get codigoVisible => CodigoReferido.paraMostrar(codigo);

  EstadoInvitacion get estado {
    if (usadaEn != null) return EstadoInvitacion.usada;
    if (DateTime.now().isAfter(expiraEn)) return EstadoInvitacion.expirada;
    return EstadoInvitacion.pendiente;
  }
}

/// Fila del ranking publico. Nunca expone el telefono completo.
@immutable
class FilaRanking {
  const FilaRanking({
    required this.posicion,
    required this.nombreVisible,
    required this.telefonoEnmascarado,
    required this.referidosValidos,
    this.soyYo = false,
  });

  final int posicion;
  final String nombreVisible;
  final String telefonoEnmascarado;
  final int referidosValidos;
  final bool soyYo;
}

/// Los tres premios que se esconden en las cajas.
enum PremioCaja {
  viaje(
    titulo: '1 viaje gratis',
    detalle: 'Tu próximo viaje en Onix Drive corre por nuestra cuenta.',
    icono: Icons.local_taxi_rounded,
  ),
  regalo(
    titulo: 'Un regalo Onix',
    detalle: 'Un regalo sorpresa de la marca, entregado por el equipo Onix.',
    icono: Icons.redeem_rounded,
  ),
  saldo(
    titulo: '\$3.000 de saldo Onix',
    detalle: 'Saldo cargado en tu cuenta de Onix Drive para tus viajes.',
    icono: Icons.account_balance_wallet_rounded,
  );

  const PremioCaja({
    required this.titulo,
    required this.detalle,
    required this.icono,
  });

  final String titulo;
  final String detalle;
  final IconData icono;

  static PremioCaja? desdeClave(String? clave) {
    for (final premio in values) {
      if (premio.name == clave) return premio;
    }
    return null;
  }
}

/// En que punto esta el reclamo del premio.
enum EstadoReclamo {
  /// Reclamado: las tres cajas estan cerradas esperando la eleccion.
  cajasListas('cajas_listas', 'Elige tu caja'),

  /// Caja abierta: el equipo Onix revisa el ticket.
  pendiente('pendiente', 'En verificación'),
  verificado('verificado', 'Verificado'),
  entregado('entregado', 'Entregado'),
  rechazado('rechazado', 'Anulado');

  const EstadoReclamo(this.clave, this.etiqueta);

  final String clave;
  final String etiqueta;

  static EstadoReclamo desdeClave(String? clave) => values.firstWhere(
        (estado) => estado.clave == clave,
        orElse: () => EstadoReclamo.pendiente,
      );
}

/// Reclamo del premio de un participante.
///
/// Mientras las cajas estan cerradas, [distribucion] llega vacia: el
/// servidor no revela donde esta cada premio hasta que se abre una caja.
@immutable
class ReclamoPremio {
  const ReclamoPremio({
    required this.id,
    required this.estado,
    required this.creadoEn,
    this.esPrueba = false,
    this.cajaElegida,
    this.premio,
    this.codigoConfirmacion,
    this.abiertoEn,
    this.distribucion = const [],
  });

  final String id;
  final EstadoReclamo estado;
  final DateTime creadoEn;
  final bool esPrueba;
  final int? cajaElegida;
  final PremioCaja? premio;

  /// Codigo normalizado de 10 caracteres. Se muestra con
  /// [codigoConfirmacionVisible].
  final String? codigoConfirmacion;
  final DateTime? abiertoEn;

  /// Premio que habia en cada caja (posiciones 0, 1 y 2). Solo se conoce
  /// despues de abrir.
  final List<PremioCaja> distribucion;

  bool get cajaAbierta => cajaElegida != null && premio != null;

  String? get codigoConfirmacionVisible {
    final codigo = codigoConfirmacion;
    if (codigo == null || codigo.length != 10) return codigo;
    return 'PRM-${codigo.substring(0, 5)}-${codigo.substring(5)}';
  }
}

/// Verificacion del telefono pendiente de confirmacion, durante el registro.
///
/// En Supabase el codigo lo envia Twilio Verify por SMS; [id] identifica el
/// registro pendiente que espera ese codigo.
@immutable
class DesafioVerificacion {
  const DesafioVerificacion({
    required this.id,
    required this.telefonoE164,
    required this.expiraEn,
    this.codigoDemo,
  });

  final String id;
  final String telefonoE164;
  final DateTime expiraEn;

  /// Solo se llena en el repositorio en memoria, que no envia SMS. Con
  /// Supabase el codigo solo existe en el SMS de Twilio y jamas vuelve al
  /// navegador.
  final String? codigoDemo;

  Duration get restante {
    final falta = expiraEn.difference(DateTime.now());
    return falta.isNegative ? Duration.zero : falta;
  }
}
