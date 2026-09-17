import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../nucleo/config_campana.dart';
import '../utiles/codigo_referido.dart';
import '../utiles/credenciales.dart';
import '../utiles/telefono.dart';
import 'modelos.dart';
import 'repositorio_referidos.dart';

/// Capacidad extra que solo tiene el repositorio de demostracion: permite
/// simular invitados y repetir el premio para mostrar el recorrido completo
/// sin backend.
abstract interface class RepositorioDemostrable {
  Future<void> simularInvitados(String idParticipante, int cantidad);

  /// Descarta el reclamo del premio para volver a abrir una caja.
  Future<void> reiniciarPremio(String idParticipante);
}

class _FilaParticipante {
  _FilaParticipante({
    required this.id,
    required this.nombre,
    required this.telefonoE164,
    required this.creadoEn,
    required this.telefonoVerificado,
    this.contrasena,
    this.huella,
  });

  final String id;
  String nombre;
  final String telefonoE164;

  /// En memoria se guarda tal cual: estos datos viven solo en la pestaña del
  /// navegador. En Supabase la contrasena se guarda cifrada con bcrypt.
  final String? contrasena;

  /// Dispositivo desde el que se registro.
  final String? huella;

  /// Dispositivos desde los que inicio sesion.
  final huellasIngreso = <String>{};

  final DateTime creadoEn;
  bool telefonoVerificado;
  bool ganadorPrueba = false;
}

/// Un codigo de invitacion de un solo uso emitido por un participante.
class _FilaInvitacion {
  _FilaInvitacion({
    required this.id,
    required this.idInvitador,
    required this.codigo,
    required this.creadoEn,
    required this.expiraEn,
  });

  final String id;
  final String idInvitador;
  final String codigo;
  final DateTime creadoEn;
  final DateTime expiraEn;
  DateTime? usadaEn;

  /// Link que entrego este codigo y dispositivo al que se entrego.
  String? idEnlace;
  String? huellaAsignada;

  /// Dispositivo y telefono del invitado, anclados a este codigo al
  /// validarlo.
  String? huellaInvitado;
  String? telefonoInvitado;
}

/// Link de invitacion: cada dispositivo que lo abre recibe su propio codigo.
class _FilaEnlace {
  _FilaEnlace({
    required this.id,
    required this.idInvitador,
    required this.token,
    required this.expiraEn,
  });

  final String id;
  final String idInvitador;
  final String token;
  final DateTime expiraEn;
}

class _FilaReferido {
  _FilaReferido({
    required this.id,
    required this.idInvitador,
    required this.nombreInvitado,
    required this.telefonoInvitado,
    required this.estado,
    required this.creadoEn,
    this.motivoRechazo,
  });

  final String id;
  final String idInvitador;
  final String nombreInvitado;
  final String telefonoInvitado;
  EstadoReferido estado;
  final DateTime creadoEn;
  String? motivoRechazo;
}

/// Registro que espera el codigo de verificacion del telefono.
class _Desafio {
  _Desafio({
    required this.id,
    required this.telefonoE164,
    required this.codigo,
    required this.expiraEn,
    required this.huella,
    required this.nombre,
    required this.contrasena,
  });

  final String id;
  final String telefonoE164;
  String codigo;
  DateTime expiraEn;
  final String huella;

  final String nombre;
  final String contrasena;

  int intentos = 0;
  DateTime ultimoEnvio = DateTime.now();
}

class _FilaReclamo {
  _FilaReclamo({
    required this.id,
    required this.distribucion,
    required this.esPrueba,
    required this.creadoEn,
  });

  final String id;
  final List<PremioCaja> distribucion;
  final bool esPrueba;
  final DateTime creadoEn;
  int? cajaElegida;
  String? codigoConfirmacion;
  DateTime? abiertoEn;
}

/// Implementacion en memoria del contrato de la campana.
///
/// Reproduce las mismas reglas que viven en Supabase (restricciones UNIQUE,
/// invitador inmutable, anclaje del dispositivo, deteccion de ciclos, limite
/// por dispositivo y cajas selladas) para que la interfaz se construya
/// contra el comportamiento definitivo y no haya sorpresas al migrar.
class RepositorioEnMemoria
    implements RepositorioReferidos, RepositorioDemostrable {
  RepositorioEnMemoria() {
    _sembrarDatosDeEjemplo();
  }

  static const _claveSesion = 'onix_sesion_participante';
  static const _maxIntentosVerificacion = 5;
  static const _segundosEntreEnvios = 45;
  static const _duracionDesafio = Duration(minutes: 10);
  static const _maxFallosIngreso = 5;
  static const _ventanaFallosIngreso = Duration(minutes: 15);
  static const _maxCodigosInvalidos = 8;
  static const _maxCodigosPorEnlace = 50;

  /// Dispositivo desde el que se hacen las operaciones.
  ///
  /// En el navegador es siempre el mismo. Las pruebas lo cambian para
  /// simular que cada invitado se registra desde su propio celular.
  String huellaDispositivo = 'navegador_local';

  final _aleatorio = Random();
  final _aleatorioSeguro = Random.secure();
  final _participantes = <String, _FilaParticipante>{};
  final _porTelefono = <String, String>{};

  /// Intentos fallidos de inicio de sesion por telefono en E.164.
  final _fallosIngreso = <String, List<DateTime>>{};
  final _referidos = <_FilaReferido>[];
  final _desafios = <String, _Desafio>{};
  final _enlaces = <String, _FilaEnlace>{};

  /// Codigos inexistentes, usados o vencidos probados desde cada
  /// dispositivo: frena a quien prueba codigos al azar.
  final _codigosInvalidos = <String, List<DateTime>>{};
  final _invitaciones = <String, _FilaInvitacion>{};
  final _porCodigoInvitacion = <String, String>{};

  /// Registros hechos desde cada dispositivo. En el servidor real se mide
  /// por IP + huella de dispositivo.
  final _registrosPorDispositivo = <String, List<DateTime>>{};

  /// Reclamo vigente de cada participante y ultimo orden de cajas que vio.
  final _reclamos = <String, _FilaReclamo>{};
  final _ultimaDistribucion = <String, List<PremioCaja>>{};

  int _secuencia = 0;

  String _nuevoId(String prefijo) => '${prefijo}_${++_secuencia}';

  Future<void> _latencia([int ms = 320]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  // ---------------------------------------------------------------------
  // Invitaciones de un solo uso
  // ---------------------------------------------------------------------

  @override
  Future<InvitacionEmitida> generarInvitacion(String idParticipante) async {
    await _latencia(180);
    _participanteObligatorio(idParticipante);
    return _invitacionAModelo(_emitirInvitacion(idParticipante));
  }

  @override
  Future<EnlaceInvitacion> miEnlace(String idParticipante) async {
    await _latencia(160);
    _participanteObligatorio(idParticipante);
    final margen = DateTime.now().add(const Duration(days: 1));
    _FilaEnlace? enlace;
    for (final candidato in _enlaces.values) {
      if (candidato.idInvitador == idParticipante &&
          candidato.expiraEn.isAfter(margen) &&
          _codigosDelEnlace(candidato.id) < _maxCodigosPorEnlace) {
        enlace = candidato;
      }
    }
    enlace ??= _crearEnlace(idParticipante);
    return EnlaceInvitacion(
      token: enlace.token,
      expiraEn: enlace.expiraEn,
      codigosEntregados: _codigosDelEnlace(enlace.id),
      maxCodigos: _maxCodigosPorEnlace,
    );
  }

  _FilaEnlace _crearEnlace(String idInvitador) {
    var token = CodigoReferido.generarToken();
    while (_enlaces.containsKey(token)) {
      token = CodigoReferido.generarToken();
    }
    final enlace = _FilaEnlace(
      id: _nuevoId('enl'),
      idInvitador: idInvitador,
      token: token,
      expiraEn: DateTime.now().add(const Duration(days: 7)),
    );
    _enlaces[token] = enlace;
    return enlace;
  }

  int _codigosDelEnlace(String idEnlace) =>
      _invitaciones.values.where((i) => i.idEnlace == idEnlace).length;

  _FilaInvitacion _emitirInvitacion(String idInvitador) {
    final fila = _FilaInvitacion(
      id: _nuevoId('inv'),
      idInvitador: idInvitador,
      codigo: _codigoInvitacionUnico(),
      creadoEn: DateTime.now(),
      expiraEn: DateTime.now()
          .add(const Duration(hours: ConfigCampana.horasExpiracionInvitacion)),
    );
    _invitaciones[fila.id] = fila;
    _porCodigoInvitacion[fila.codigo] = fila.id;
    return fila;
  }

  @override
  Future<List<InvitacionEmitida>> misInvitaciones(
    String idParticipante,
  ) async {
    await _latencia(180);
    final propias = _invitaciones.values
        .where((f) => f.idInvitador == idParticipante)
        .toList()
      ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return propias.map(_invitacionAModelo).toList();
  }

  @override
  Future<List<EventoReferido>> misReferidos(String idParticipante) async {
    await _latencia(220);
    final propios = _referidos
        .where((r) => r.idInvitador == idParticipante)
        .toList()
      ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

    return [
      for (final fila in propios)
        EventoReferido(
          id: fila.id,
          nombreInvitado: fila.nombreInvitado,
          telefonoInvitado: fila.telefonoInvitado,
          estado: fila.estado,
          creadoEn: fila.creadoEn,
          motivoRechazo: fila.motivoRechazo,
        ),
    ];
  }

  @override
  Future<Participante> refrescarParticipante(String idParticipante) async {
    await _latencia(160);
    return _aModelo(_participanteObligatorio(idParticipante));
  }

  // ---------------------------------------------------------------------
  // Sesion
  // ---------------------------------------------------------------------

  @override
  Future<Participante?> sesionActual() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_claveSesion);
    if (id == null) return null;
    final fila = _participantes[id];
    if (fila == null) return null;
    return _aModelo(fila);
  }

  @override
  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveSesion);
  }

  Future<void> _guardarSesion(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveSesion, id);
  }

  // ---------------------------------------------------------------------
  // Registro y verificacion
  // ---------------------------------------------------------------------

  @override
  Future<DesafioVerificacion> iniciarRegistro({
    required String nombre,
    required String contrasena,
    required String telefono,
    required PaisTelefono pais,
  }) async {
    await _latencia();

    final nombreLimpio = nombre.trim();
    if (nombreLimpio.length < 3) {
      throw const ErrorReferidos(
        MotivoError.desconocido,
        'Escribe tu nombre completo para continuar.',
      );
    }

    final errorContrasena = UtilesCredenciales.errorContrasena(contrasena);
    if (errorContrasena != null) {
      throw ErrorReferidos(
        MotivoError.contrasenaInvalida,
        'Contraseña no válida: ${errorContrasena.toLowerCase()}.',
      );
    }

    // Reglas 1 y 2: movil valido del pais elegido y sin pinta de falso.
    final e164 = _telefonoValidado(telefono, pais);

    // Regla 3: un telefono = una cuenta.
    if (_porTelefono.containsKey(e164)) {
      throw const ErrorReferidos(
        MotivoError.telefonoYaRegistrado,
        'Este número ya tiene una cuenta. Ingresa con tu celular y '
        'contraseña.',
      );
    }

    // Regla 4: limite de registros por dispositivo en 24 horas.
    final huella = huellaDispositivo;
    if (_registrosRecientes(huella).length >=
        ConfigCampana.maxRegistrosPorDispositivo) {
      throw const ErrorReferidos(
        MotivoError.limiteDispositivo,
        'Se registraron demasiadas cuentas desde este dispositivo. '
        'Intenta de nuevo en 24 horas.',
      );
    }

    final desafio = _Desafio(
      id: _nuevoId('otp'),
      telefonoE164: e164,
      codigo: _codigoVerificacion(),
      expiraEn: DateTime.now().add(_duracionDesafio),
      nombre: nombreLimpio,
      contrasena: contrasena,
      huella: huella,
    );
    _desafios[desafio.id] = desafio;
    return _desafioAModelo(desafio);
  }

  @override
  Future<Participante> iniciarSesion({
    required String telefono,
    required PaisTelefono pais,
    required String contrasena,
  }) async {
    await _latencia();

    final e164 = UtilesTelefono.aE164(telefono, pais);
    if (e164 == null || contrasena.isEmpty) {
      throw const ErrorReferidos(
        MotivoError.credencialesIncorrectas,
        'Escribe tu celular y tu contraseña.',
      );
    }

    // Freno a la fuerza bruta: pocos intentos fallidos por numero.
    final limite = DateTime.now().subtract(_ventanaFallosIngreso);
    final fallos = _fallosIngreso.putIfAbsent(e164, () => [])
      ..removeWhere((fecha) => fecha.isBefore(limite));
    if (fallos.length >= _maxFallosIngreso) {
      throw const ErrorReferidos(
        MotivoError.demasiadosIntentos,
        'Demasiados intentos fallidos. Espera 15 minutos antes de volver a '
        'intentar.',
      );
    }

    final id = _porTelefono[e164];
    final fila = id == null ? null : _participantes[id];
    // Mismo mensaje si la cuenta no existe o si la clave no coincide: asi
    // no se puede averiguar que numeros estan registrados.
    if (fila == null || fila.contrasena != contrasena) {
      fallos.add(DateTime.now());
      throw const ErrorReferidos(
        MotivoError.credencialesIncorrectas,
        'Celular o contraseña incorrectos.',
      );
    }

    _fallosIngreso.remove(e164);
    fila.huellasIngreso.add(huellaDispositivo);
    await _guardarSesion(fila.id);
    return _aModelo(fila);
  }

  @override
  Future<DesafioVerificacion> reenviarCodigo(String idDesafio) async {
    await _latencia(200);
    return _reenviar(_desafios, idDesafio);
  }

  @override
  Future<Participante> confirmarVerificacion({
    required String idDesafio,
    required String codigo,
  }) async {
    await _latencia();
    final desafio = _revisarSms(_desafios, idDesafio, codigo);

    // Entre el paso 1 y el paso 2 pudo registrarse el mismo numero.
    if (_porTelefono.containsKey(desafio.telefonoE164)) {
      throw const ErrorReferidos(
        MotivoError.telefonoYaRegistrado,
        'Este número ya tiene una cuenta. Ingresa con tu celular y '
        'contraseña.',
      );
    }

    // Registro nuevo: aqui recien nace el participante, ya con telefono
    // verificado.
    final fila = _FilaParticipante(
      id: _nuevoId('par'),
      nombre: desafio.nombre,
      telefonoE164: desafio.telefonoE164,
      contrasena: desafio.contrasena,
      creadoEn: DateTime.now(),
      telefonoVerificado: true,
      huella: desafio.huella,
    );

    _participantes[fila.id] = fila;
    _porTelefono[fila.telefonoE164] = fila.id;
    _registrosPorDispositivo
        .putIfAbsent(desafio.huella, () => [])
        .add(DateTime.now());

    await _guardarSesion(fila.id);
    return _aModelo(fila);
  }

  // ---------------------------------------------------------------------
  // Invitados: link, codigo y validacion sin cuenta ni SMS
  // ---------------------------------------------------------------------

  @override
  Future<CodigoAsignado> obtenerCodigoDeEnlace(String tokenEnlace) async {
    await _latencia(220);
    final huella = huellaDispositivo;
    _frenarAdivinanzas(huella);

    final token =
        tokenEnlace.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final enlace = _enlaces[token];
    if (enlace == null) {
      _codigosInvalidosRecientes(huella).add(DateTime.now());
      throw const ErrorReferidos(
        MotivoError.codigoInexistente,
        'Este link de invitación no existe. Revisa que lo hayas abierto '
        'completo.',
      );
    }
    final invitador = _participantes[enlace.idInvitador]!;
    if (_esDispositivoDe(invitador, huella)) {
      throw const ErrorReferidos(
        MotivoError.dispositivoDelInvitador,
        'Este es tu propio link de invitación: compártelo por WhatsApp para '
        'que cada contacto reciba su código.',
      );
    }

    // El mismo dispositivo recibe siempre el mismo codigo de este link.
    _FilaInvitacion? fila;
    for (final invitacion in _invitaciones.values) {
      if (invitacion.idEnlace == enlace.id &&
          invitacion.huellaAsignada == huella) {
        fila = invitacion;
        break;
      }
    }

    if (fila == null) {
      if (DateTime.now().isAfter(enlace.expiraEn)) {
        throw const ErrorReferidos(
          MotivoError.codigoExpirado,
          'Este link de invitación venció. Pide uno nuevo a quien te invitó.',
        );
      }
      if (_codigosDelEnlace(enlace.id) >= _maxCodigosPorEnlace) {
        throw const ErrorReferidos(
          MotivoError.demasiadosIntentos,
          'Este link ya entregó todos sus códigos. Pide uno nuevo a quien te '
          'invitó.',
        );
      }
      fila = _emitirInvitacion(enlace.idInvitador)
        ..idEnlace = enlace.id
        ..huellaAsignada = huella;
    }

    return CodigoAsignado(
      codigo: fila.codigo,
      expiraEn: fila.expiraEn,
      usado: fila.usadaEn != null,
      nombreInvitador: _primerNombre(invitador.nombre),
    );
  }

  @override
  Future<ResultadoCanje> validarCodigo({
    required String codigoInvitacion,
    required String telefono,
    required PaisTelefono pais,
  }) async {
    await _latencia();
    final huella = huellaDispositivo;
    _frenarAdivinanzas(huella);

    final codigo = CodigoReferido.normalizar(codigoInvitacion);
    if (!CodigoReferido.esValido(codigo)) {
      throw const ErrorReferidos(
        MotivoError.codigoMalFormado,
        'Ese código de invitación no es válido. Revisa que esté completo.',
      );
    }
    final e164 = _telefonoValidado(telefono, pais);

    final _FilaInvitacion invitacion;
    try {
      invitacion = _revisarCanje(codigo, e164, huella);
    } on ErrorReferidos catch (error) {
      if (const {
        MotivoError.codigoInexistente,
        MotivoError.codigoYaUsado,
        MotivoError.codigoExpirado,
      }.contains(error.motivo)) {
        _codigosInvalidosRecientes(huella).add(DateTime.now());
      }
      rethrow;
    }

    final ahora = DateTime.now();
    invitacion
      ..usadaEn = ahora
      ..huellaInvitado = huella
      ..telefonoInvitado = e164;
    _referidos.add(
      _FilaReferido(
        id: _nuevoId('ref'),
        idInvitador: invitacion.idInvitador,
        nombreInvitado: 'Invitado',
        telefonoInvitado: e164,
        estado: EstadoReferido.valido,
        creadoEn: ahora,
      ),
    );

    return ResultadoCanje(
      codigo: invitacion.codigo,
      telefonoE164: e164,
      validadoEn: ahora,
      nombreInvitador:
          _primerNombre(_participantes[invitacion.idInvitador]?.nombre ?? ''),
    );
  }

  void _frenarAdivinanzas(String huella) {
    if (_codigosInvalidosRecientes(huella).length >= _maxCodigosInvalidos) {
      throw const ErrorReferidos(
        MotivoError.demasiadosIntentos,
        'Probaste demasiados códigos que no sirven. Intenta de nuevo en una '
        'hora.',
      );
    }
  }

  static String _primerNombre(String nombre) =>
      nombre.trim().split(RegExp(r'\s+')).first;

  /// Todas las reglas del canje, igual que `fn_revisar_canje` en la base.
  _FilaInvitacion _revisarCanje(String codigo, String e164, String huella) {
    final invitacion = _invitacionVigente(codigo);
    final invitador = _participantes[invitacion.idInvitador]!;

    // Un codigo entregado por un link solo lo valida el dispositivo que
    // abrio el link.
    if (invitacion.huellaAsignada != null &&
        invitacion.huellaAsignada != huella) {
      throw const ErrorReferidos(
        MotivoError.dispositivoNoIdentificado,
        'Este código se entregó a otro dispositivo. Abre el link de '
        'invitación desde tu propio celular.',
      );
    }

    if (invitador.telefonoE164 == e164) {
      throw const ErrorReferidos(
        MotivoError.autoReferido,
        'No puedes invitarte a ti mismo.',
      );
    }

    // Anclaje del dispositivo.
    _revisarAnclaje(invitador, huella);

    // Anclaje del telefono: un numero acepta una sola invitacion.
    final telefonoYaInvitado =
        _invitaciones.values.any((i) => i.telefonoInvitado == e164) ||
            _referidos.any((r) => r.telefonoInvitado == e164);
    if (telefonoYaInvitado) {
      throw const ErrorReferidos(
        MotivoError.yaTieneInvitador,
        'Este número ya validó una invitación. Cada persona puede ser '
        'invitada una sola vez.',
      );
    }

    if (_esCircular(invitador, e164)) {
      throw const ErrorReferidos(
        MotivoError.referidoCircular,
        'No puedes validar el código de alguien a quien tú invitaste.',
      );
    }
    return invitacion;
  }

  DesafioVerificacion _reenviar(Map<String, _Desafio> esperas, String id) {
    final desafio = esperas[id];
    if (desafio == null) {
      throw const ErrorReferidos(
        MotivoError.verificacionExpirada,
        'La verificación expiró. Vuelve a empezar.',
      );
    }

    final espera = DateTime.now().difference(desafio.ultimoEnvio).inSeconds;
    if (espera < _segundosEntreEnvios) {
      throw ErrorReferidos(
        MotivoError.demasiadosIntentos,
        'Espera ${_segundosEntreEnvios - espera} segundos para pedir otro '
        'código.',
      );
    }

    desafio
      ..codigo = _codigoVerificacion()
      ..expiraEn = DateTime.now().add(_duracionDesafio)
      ..ultimoEnvio = DateTime.now()
      ..intentos = 0;
    return _desafioAModelo(desafio);
  }

  /// Revisa el codigo del SMS y, si coincide, saca la espera de la lista.
  _Desafio _revisarSms(
    Map<String, _Desafio> esperas,
    String id,
    String codigo,
  ) {
    final desafio = esperas[id];
    if (desafio == null || DateTime.now().isAfter(desafio.expiraEn)) {
      esperas.remove(id);
      throw const ErrorReferidos(
        MotivoError.verificacionExpirada,
        'El código expiró. Pide uno nuevo.',
      );
    }

    if (desafio.intentos >= _maxIntentosVerificacion) {
      esperas.remove(id);
      throw const ErrorReferidos(
        MotivoError.demasiadosIntentos,
        'Demasiados intentos fallidos. Vuelve a solicitar el código.',
      );
    }

    if (UtilesTelefono.soloDigitos(codigo) != desafio.codigo) {
      desafio.intentos++;
      throw const ErrorReferidos(
        MotivoError.codigoVerificacionIncorrecto,
        'El código no coincide. Revisa el mensaje que te enviamos.',
      );
    }

    esperas.remove(id);
    return desafio;
  }

  String _telefonoValidado(String telefono, PaisTelefono pais) {
    final e164 = UtilesTelefono.aE164(telefono, pais);
    if (e164 == null) {
      throw ErrorReferidos(
        MotivoError.telefonoInvalido,
        pais.mensajeFormatoInvalido,
      );
    }
    // Descartar numeros obviamente falsos antes de gastar un SMS.
    if (UtilesTelefono.pareceSospechoso(e164, pais)) {
      throw const ErrorReferidos(
        MotivoError.numeroSospechoso,
        'Ese número no parece real. Usa tu número personal para participar.',
      );
    }
    return e164;
  }

  List<DateTime> _codigosInvalidosRecientes(String huella) {
    final limite = DateTime.now().subtract(const Duration(hours: 1));
    return _codigosInvalidos.putIfAbsent(huella, () => [])
      ..removeWhere((fecha) => fecha.isBefore(limite));
  }

  // ---------------------------------------------------------------------
  // Premio: las tres cajas
  // ---------------------------------------------------------------------

  @override
  Future<ReclamoPremio?> miReclamo(String idParticipante) async {
    await _latencia(140);
    _participanteObligatorio(idParticipante);
    final reclamo = _reclamos[idParticipante];
    return reclamo == null ? null : _reclamoAModelo(reclamo);
  }

  @override
  Future<ReclamoPremio> reclamarPremio(String idParticipante) async {
    await _latencia(260);
    final participante = _participanteObligatorio(idParticipante);

    // Idempotente: no hay forma de pedir un orden nuevo de cajas.
    final existente = _reclamos[idParticipante];
    if (existente != null) return _reclamoAModelo(existente);

    final tickets = _contarValidos(idParticipante);
    if (tickets < ConfigCampana.metaTickets && !participante.ganadorPrueba) {
      throw ErrorReferidos(
        MotivoError.premioNoDisponible,
        'Te faltan ${ConfigCampana.metaTickets - tickets} tickets para '
        'reclamar tu premio.',
      );
    }

    final reclamo = _FilaReclamo(
      id: _nuevoId('rec'),
      distribucion: _distribucionAleatoria(
        evitar: _ultimaDistribucion[idParticipante],
      ),
      esPrueba: tickets < ConfigCampana.metaTickets,
      creadoEn: DateTime.now(),
    );
    _reclamos[idParticipante] = reclamo;
    _ultimaDistribucion[idParticipante] = reclamo.distribucion;
    return _reclamoAModelo(reclamo);
  }

  @override
  Future<ReclamoPremio> abrirCaja({
    required String idParticipante,
    required String idReclamo,
    required int caja,
  }) async {
    await _latencia(420);
    _participanteObligatorio(idParticipante);

    if (caja < 0 || caja > 2) {
      throw const ErrorReferidos(MotivoError.cajaInvalida, 'Esa caja no existe.');
    }

    final reclamo = _reclamos[idParticipante];
    if (reclamo == null || reclamo.id != idReclamo) {
      throw const ErrorReferidos(
        MotivoError.premioNoDisponible,
        'No encontramos tu reclamo de premio. Recarga la página.',
      );
    }

    // Solo la primera apertura cuenta.
    if (reclamo.cajaElegida == null) {
      reclamo
        ..cajaElegida = caja
        ..codigoConfirmacion = _codigoConfirmacion()
        ..abiertoEn = DateTime.now();
    }
    return _reclamoAModelo(reclamo);
  }

  // ---------------------------------------------------------------------
  // Solo demostracion
  // ---------------------------------------------------------------------

  @override
  Future<void> simularInvitados(String idParticipante, int cantidad) async {
    await _latencia(260);
    const nombres = [
      'Camila Muñoz',
      'Matías Fuentes',
      'Javiera Rojas',
      'Sebastián Pérez',
      'Constanza Vidal',
      'Ignacio Soto',
      'Antonia Contreras',
      'Benjamín Araya',
      'Valentina Herrera',
      'Cristóbal Núñez',
    ];
    for (var i = 0; i < cantidad; i++) {
      _referidos.add(
        _FilaReferido(
          id: _nuevoId('ref'),
          idInvitador: idParticipante,
          nombreInvitado: nombres[_aleatorio.nextInt(nombres.length)],
          telefonoInvitado: _telefonoAleatorio(),
          estado: EstadoReferido.valido,
          creadoEn: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> reiniciarPremio(String idParticipante) async {
    await _latencia(160);
    _reclamos.remove(idParticipante);
  }

  // ---------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------

  _FilaParticipante _participanteObligatorio(String idParticipante) {
    final fila = _participantes[idParticipante];
    if (fila == null) {
      throw const ErrorReferidos(
        MotivoError.noRegistrado,
        'Tu sesión expiró. Vuelve a ingresar.',
      );
    }
    return fila;
  }

  /// Invitacion que existe, no se uso y no vencio; si no, el error exacto.
  _FilaInvitacion _invitacionVigente(String codigo) {
    final fila = _invitacionPorCodigo(codigo);
    if (fila == null) {
      throw const ErrorReferidos(
        MotivoError.codigoInexistente,
        'No encontramos ese código de invitación.',
      );
    }
    if (fila.usadaEn != null) {
      throw const ErrorReferidos(
        MotivoError.codigoYaUsado,
        'Ese código de invitación ya fue usado por otra persona. Pide uno '
        'nuevo a quien te invitó.',
      );
    }
    if (DateTime.now().isAfter(fila.expiraEn)) {
      throw const ErrorReferidos(
        MotivoError.codigoExpirado,
        'Ese código de invitación venció. Pide uno nuevo a quien te invitó.',
      );
    }
    return fila;
  }

  /// Un dispositivo se ancla a un unico codigo en toda la campana, y no
  /// puede ser el de quien invita.
  void _revisarAnclaje(_FilaParticipante invitador, String huella) {
    final yaAnclado =
        _invitaciones.values.any((i) => i.huellaInvitado == huella);
    if (yaAnclado) {
      throw const ErrorReferidos(
        MotivoError.dispositivoYaAnclado,
        'Este dispositivo ya se usó para aceptar una invitación. Cada '
        'invitado debe validar su código desde su propio celular.',
      );
    }
    if (_esDispositivoDe(invitador, huella)) {
      throw const ErrorReferidos(
        MotivoError.dispositivoDelInvitador,
        'Este código no se puede usar desde el dispositivo de quien te '
        'invitó. Valídalo desde tu propio celular.',
      );
    }
  }

  bool _esDispositivoDe(_FilaParticipante participante, String huella) =>
      participante.huella == huella ||
      participante.huellasIngreso.contains(huella);

  List<DateTime> _registrosRecientes(String huella) {
    final limite = DateTime.now().subtract(const Duration(hours: 24));
    return _registrosPorDispositivo.putIfAbsent(huella, () => [])
      ..removeWhere((fecha) => fecha.isBefore(limite));
  }

  /// Fisher-Yates con aleatoriedad criptografica, igual que en la base.
  List<PremioCaja> _distribucionAleatoria({List<PremioCaja>? evitar}) {
    while (true) {
      final orden = [...PremioCaja.values];
      for (var i = orden.length - 1; i > 0; i--) {
        final j = _aleatorioSeguro.nextInt(i + 1);
        final temporal = orden[i];
        orden[i] = orden[j];
        orden[j] = temporal;
      }
      final repetido = evitar != null &&
          List.generate(orden.length, (i) => orden[i] == evitar[i])
              .every((igual) => igual);
      if (!repetido) return List.unmodifiable(orden);
    }
  }

  String _codigoConfirmacion() => List.generate(
        10,
        (_) => CodigoReferido
            .alfabeto[_aleatorioSeguro.nextInt(CodigoReferido.alfabeto.length)],
      ).join();

  ReclamoPremio _reclamoAModelo(_FilaReclamo fila) {
    final abierta = fila.cajaElegida != null;
    return ReclamoPremio(
      id: fila.id,
      estado: abierta ? EstadoReclamo.pendiente : EstadoReclamo.cajasListas,
      creadoEn: fila.creadoEn,
      esPrueba: fila.esPrueba,
      cajaElegida: fila.cajaElegida,
      premio: abierta ? fila.distribucion[fila.cajaElegida!] : null,
      codigoConfirmacion: fila.codigoConfirmacion,
      abiertoEn: fila.abiertoEn,
      // Igual que el servidor: el orden solo sale una vez abierta la caja.
      distribucion: abierta ? fila.distribucion : const [],
    );
  }

  DesafioVerificacion _desafioAModelo(_Desafio desafio) =>
      DesafioVerificacion(
        id: desafio.id,
        telefonoE164: desafio.telefonoE164,
        expiraEn: desafio.expiraEn,
        // Con Supabase este campo viaja vacio: el codigo solo existe en el
        // SMS que envia Twilio.
        codigoDemo: desafio.codigo,
      );

  String _codigoVerificacion() =>
      (100000 + _aleatorio.nextInt(900000)).toString();

  String _codigoInvitacionUnico() {
    var codigo = CodigoReferido.generar();
    while (_porCodigoInvitacion.containsKey(codigo)) {
      codigo = CodigoReferido.generar();
    }
    return codigo;
  }

  _FilaInvitacion? _invitacionPorCodigo(String codigo) {
    final id = _porCodigoInvitacion[codigo];
    return id == null ? null : _invitaciones[id];
  }

  InvitacionEmitida _invitacionAModelo(_FilaInvitacion fila) =>
      InvitacionEmitida(
        id: fila.id,
        codigo: fila.codigo,
        creadoEn: fila.creadoEn,
        expiraEn: fila.expiraEn,
        usadaEn: fila.usadaEn,
        telefonoInvitado: fila.telefonoInvitado == null
            ? null
            : UtilesTelefono.enmascarar(fila.telefonoInvitado!),
      );

  /// Un ciclo existe cuando quien invita (o alguien de su cadena hacia
  /// arriba) fue invitado justamente por el numero que ahora valida el
  /// codigo. Como el invitado no tiene cuenta, la cadena se sigue por los
  /// telefonos anclados a cada invitacion.
  bool _esCircular(_FilaParticipante invitador, String telefonoNuevo) {
    var actual = invitador;
    for (var saltos = 0; saltos < 50; saltos++) {
      _FilaInvitacion? recibida;
      for (final invitacion in _invitaciones.values) {
        if (invitacion.telefonoInvitado == actual.telefonoE164) {
          recibida = invitacion;
          break;
        }
      }
      if (recibida == null) return false;
      final padre = _participantes[recibida.idInvitador]!;
      if (padre.telefonoE164 == telefonoNuevo) return true;
      actual = padre;
    }
    return false;
  }

  int _contarValidos(String idParticipante) => _referidos
      .where((r) =>
          r.idInvitador == idParticipante && r.estado == EstadoReferido.valido)
      .length;

  int _contarPendientes(String idParticipante) => _referidos
      .where((r) =>
          r.idInvitador == idParticipante &&
          r.estado == EstadoReferido.pendiente)
      .length;

  Participante _aModelo(_FilaParticipante fila) => Participante(
        id: fila.id,
        nombre: fila.nombre,
        telefonoE164: fila.telefonoE164,
        creadoEn: fila.creadoEn,
        telefonoVerificado: fila.telefonoVerificado,
        referidosValidos: _contarValidos(fila.id),
        referidosPendientes: _contarPendientes(fila.id),
        ganadorPrueba: fila.ganadorPrueba,
      );

  String _telefonoAleatorio() {
    final numero = 90000000 + _aleatorio.nextInt(9999999);
    return '+569$numero';
  }

  /// Datos de vitrina para que la landing no se vea vacia en desarrollo.
  void _sembrarDatosDeEjemplo() {
    const semilla = <(String, int, int)>[
      ('Camila Muñoz', 47, 2),
      ('Matías Fuentes', 41, 1),
      ('Javiera Rojas', 38, 3),
      ('Sebastián Pérez', 33, 0),
      ('Constanza Vidal', 29, 2),
      ('Ignacio Soto', 24, 1),
      ('Antonia Contreras', 21, 0),
      ('Benjamín Araya', 17, 4),
      ('Valentina Herrera', 14, 1),
      ('Cristóbal Núñez', 11, 0),
      ('Fernanda Silva', 8, 2),
      ('Diego Morales', 6, 1),
    ];

    var dias = 40;
    for (final (nombre, validos, pendientes) in semilla) {
      final fila = _FilaParticipante(
        id: _nuevoId('par'),
        nombre: nombre,
        telefonoE164: _telefonoAleatorio(),
        creadoEn: DateTime.now().subtract(Duration(days: dias--)),
        telefonoVerificado: true,
        huella: 'semilla_$dias',
      );
      _participantes[fila.id] = fila;
      _porTelefono[fila.telefonoE164] = fila.id;

      for (var i = 0; i < validos; i++) {
        _referidos.add(
          _FilaReferido(
            id: _nuevoId('ref'),
            idInvitador: fila.id,
            nombreInvitado: 'Invitado ${i + 1}',
            telefonoInvitado: _telefonoAleatorio(),
            estado: EstadoReferido.valido,
            creadoEn: DateTime.now().subtract(Duration(hours: 6 + i * 5)),
          ),
        );
      }
      for (var i = 0; i < pendientes; i++) {
        _referidos.add(
          _FilaReferido(
            id: _nuevoId('ref'),
            idInvitador: fila.id,
            nombreInvitado: 'Invitado pendiente ${i + 1}',
            telefonoInvitado: _telefonoAleatorio(),
            estado: EstadoReferido.pendiente,
            creadoEn: DateTime.now().subtract(Duration(hours: 2 + i)),
          ),
        );
      }
    }

    // Un referido rechazado de ejemplo, para que el panel muestre los tres
    // estados posibles del embudo.
    final primero = _participantes.values.first;
    _referidos.add(
      _FilaReferido(
        id: _nuevoId('ref'),
        idInvitador: primero.id,
        nombreInvitado: 'Registro duplicado',
        telefonoInvitado: _telefonoAleatorio(),
        estado: EstadoReferido.rechazado,
        creadoEn: DateTime.now().subtract(const Duration(hours: 30)),
        motivoRechazo: 'Dispositivo ya anclado a otra invitación',
      ),
    );
  }
}
