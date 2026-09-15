import '../utiles/telefono.dart';
import 'modelos.dart';

/// Causas por las que una operacion de la campana puede fallar.
///
/// Cada caso corresponde a una regla anti-fraude concreta; la interfaz las
/// traduce a un mensaje entendible para la persona.
enum MotivoError {
  telefonoInvalido,
  numeroSospechoso,
  usuarioInvalido,
  usuarioYaRegistrado,
  contrasenaInvalida,
  credencialesIncorrectas,
  servicioSmsNoDisponible,
  telefonoYaRegistrado,
  codigoInexistente,
  codigoMalFormado,
  codigoYaUsado,
  codigoExpirado,
  autoReferido,
  referidoCircular,
  yaTieneInvitador,
  limiteDispositivo,
  demasiadosIntentos,
  codigoVerificacionIncorrecto,
  verificacionExpirada,
  noRegistrado,
  dispositivoNoIdentificado,
  dispositivoYaAnclado,
  dispositivoDelInvitador,
  premioNoDisponible,
  cajaInvalida,
  desconocido,
}

/// Error de dominio de la campana de referidos.
class ErrorReferidos implements Exception {
  const ErrorReferidos(this.motivo, this.mensaje);

  final MotivoError motivo;
  final String mensaje;

  @override
  String toString() => 'ErrorReferidos(${motivo.name}): $mensaje';
}

/// Contrato de datos de la campana.
///
/// La interfaz de usuario solo conoce esta abstraccion. Hoy la implementa
/// [RepositorioEnMemoria] para desarrollo; manana la implementara
/// `RepositorioSupabase` sin que haya que tocar una sola pantalla.
abstract interface class RepositorioReferidos {
  /// Ranking publico de invitadores.
  Future<List<FilaRanking>> obtenerRanking({
    int limite = 10,
    String? idParticipante,
  });

  /// Participante de la sesion guardada en este navegador, si existe.
  Future<Participante?> sesionActual();

  /// Cierra la sesion local (no borra datos del servidor).
  Future<void> cerrarSesion();

  /// Genera un codigo de invitacion nuevo y de un solo uso, listo para
  /// compartir por WhatsApp con una persona concreta.
  Future<InvitacionEmitida> generarInvitacion(String idParticipante);

  /// Codigos de invitacion que emitio este participante, del mas reciente
  /// al mas antiguo (pendientes, usados y vencidos).
  Future<List<InvitacionEmitida>> misInvitaciones(String idParticipante);

  /// Paso 1 del registro: valida los datos y envia el codigo de verificacion
  /// por SMS.
  ///
  /// Aqui se aplican las reglas que no dependen de haber verificado el
  /// telefono todavia (formato, telefono o usuario ya registrados,
  /// contrasena debil, autorreferido, codigo inexistente, limite por
  /// dispositivo y anclaje: si trae codigo, el dispositivo no puede haber
  /// aceptado otra invitacion ni ser el de quien invita). La cuenta todavia
  /// NO existe al terminar este paso.
  Future<DesafioVerificacion> iniciarRegistro({
    required String nombre,
    required String nombreUsuario,
    required String contrasena,
    required String telefono,
    required PaisTelefono pais,
    String? codigoInvitador,
  });

  /// Ingreso de alguien que ya tiene cuenta: usuario y contrasena, sin SMS.
  Future<Participante> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
  });

  /// Paso 2 del registro: confirma el codigo recibido, crea la cuenta y
  /// devuelve al participante con la sesion abierta.
  ///
  /// Solo en este momento el dispositivo queda anclado al codigo y el
  /// referido pasa a `valido`, sumando un ticket a quien invito.
  Future<Participante> confirmarVerificacion({
    required String idDesafio,
    required String codigo,
  });

  /// Reenvia el codigo de verificacion respetando el limite de frecuencia.
  Future<DesafioVerificacion> reenviarCodigo(String idDesafio);

  /// Invitados de un participante, del mas reciente al mas antiguo.
  Future<List<EventoReferido>> misReferidos(String idParticipante);

  /// Vuelve a leer al participante para refrescar contadores.
  Future<Participante> refrescarParticipante(String idParticipante);

  /// Reclamo de premio vigente del participante, o `null` si todavia no
  /// reclamo. Con las cajas cerradas no trae la distribucion de premios.
  Future<ReclamoPremio?> miReclamo(String idParticipante);

  /// «Reclamar premio»: exige la meta de tickets (o el modo de prueba que
  /// habilita el admin) y deja las tres cajas listas. Si ya existia un
  /// reclamo devuelve ese mismo: no se puede volver a barajar.
  Future<ReclamoPremio> reclamarPremio(String idParticipante);

  /// Abre la caja [caja] (0, 1 o 2). Solo la primera apertura cuenta; las
  /// siguientes devuelven la caja que ya quedo abierta.
  Future<ReclamoPremio> abrirCaja({
    required String idParticipante,
    required String idReclamo,
    required int caja,
  });
}
