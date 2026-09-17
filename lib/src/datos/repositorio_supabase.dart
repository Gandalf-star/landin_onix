import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../nucleo/config_campana.dart';
import '../utiles/codigo_referido.dart';
import '../utiles/credenciales.dart';
import '../utiles/dispositivo.dart';
import '../utiles/telefono.dart';
import 'modelos.dart';
import 'repositorio_referidos.dart';

/// Implementacion de [RepositorioReferidos] sobre el proyecto Supabase.
///
/// Registro: telefono verificado con Twilio
/// -----------------------------------------
/// Crear una cuenta (solo quien invita) pasa por la Edge Function
/// `verificar-telefono` (`supabase/functions/verificar-telefono`). Ella
/// guarda los datos, pide a Twilio Verify que envie el SMS y solo crea la
/// cuenta cuando Twilio aprueba el codigo. Las credenciales de Twilio viven
/// como secretos de esa funcion: el navegador nunca las ve.
///
/// Invitados: link y codigo, sin cuenta ni SMS
/// -------------------------------------------
/// Quien abre un link de invitacion recibe su propio codigo
/// (`invitado_obtener_codigo`) y lo valida con su celular
/// (`invitado_validar_codigo`). La base ancla el codigo al telefono y al
/// dispositivo y aplica las reglas anti-fraude.
///
/// Ingreso: celular y contrasena
/// -----------------------------
/// Quien ya tiene cuenta entra con `cuenta_iniciar_sesion`, sin SMS. La base
/// compara la contrasena con bcrypt y limita los intentos fallidos.
///
/// Las reglas anti-fraude viven en Postgres y se aplican en el servidor:
///   - un telefono, una cuenta (restriccion UNIQUE);
///   - una invitacion canjeada es inmutable (trigger);
///   - el dispositivo y el telefono del invitado quedan anclados a su
///     codigo (indices unicos);
///   - sin autorreferidos ni cadenas circulares;
///   - limite de registros por dispositivo, de SMS y de intentos.
///
/// Premio: las tres cajas
/// ----------------------
/// El orden de los premios lo decide y lo guarda la base. Este cliente solo
/// recibe la distribucion despues de abrir una caja.
class RepositorioSupabase implements RepositorioReferidos {
  RepositorioSupabase(this.cliente);

  final SupabaseClient cliente;

  /// Nombre de la Edge Function que habla con Twilio.
  static const funcionVerificacion = 'verificar-telefono';

  static const _claveToken = 'onix_token_sesion';
  static const _claveHuella = 'onix_huella_dispositivo';

  // ---------------------------------------------------------------------
  // Sesion y dispositivo
  // ---------------------------------------------------------------------

  /// La sesion es un token opaco que entrega la base al crear la cuenta o al
  /// iniciar sesion. Sin el no se puede leer la ficha de nadie, aunque se
  /// conozca su identificador.
  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveToken);
  }

  Future<String> _tokenObligatorio() async {
    final token = await _token();
    if (token == null) {
      throw const ErrorReferidos(
        MotivoError.noRegistrado,
        'Tu sesión expiró. Vuelve a ingresar.',
      );
    }
    return token;
  }

  /// Identificador estable de este navegador. No identifica a la persona:
  /// permite aplicar el limite de registros por dispositivo y anclar el
  /// dispositivo del invitado a su codigo. Si alguien limpia los datos del
  /// sitio se genera uno nuevo, pero la firma del navegador que se envia
  /// junto al registro deja el rastro para el panel admin.
  Future<String> _huellaDispositivo() async {
    final prefs = await SharedPreferences.getInstance();
    var huella = prefs.getString(_claveHuella);
    if (huella == null) {
      final aleatorio = Random.secure();
      final bytes = List.generate(16, (_) => aleatorio.nextInt(256));
      huella = 'nav_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_claveHuella, huella);
    }
    return huella;
  }

  @override
  Future<Participante?> sesionActual() {
    return _proteger(() async {
      final token = await _token();
      if (token == null) return null;
      final json = await cliente.rpc<dynamic>(
        'sesion_participante',
        params: {'p_token': token},
      );
      if (json == null) {
        // La sesion vencio o se cerro desde otro lado: se olvida el token.
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_claveToken);
        return null;
      }
      return _participanteDesde(json as Map<String, dynamic>);
    });
  }

  @override
  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_claveToken);
    if (token != null) {
      try {
        await cliente.rpc<dynamic>(
          'sesion_cerrar',
          params: {'p_token': token},
        );
      } on PostgrestException {
        // Cerrar la sesion local no puede fallar por culpa del servidor.
      }
    }
    await prefs.remove(_claveToken);
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
  }) {
    return _proteger(() async {
      if (nombre.trim().length < 3) {
        throw const ErrorReferidos(
          MotivoError.desconocido,
          'Escribe tu nombre completo.',
        );
      }
      final json = await _llamarVerificacion({
        'accion': 'iniciar_registro',
        'nombre': nombre.trim(),
        'contrasena': _contrasenaValidada(contrasena),
        'telefono': _telefonoValidado(telefono, pais),
        'huella': await _huellaDispositivo(),
        'dispositivo': (await UtilesDispositivo.leer()).aJson(),
      });
      return _desafioDesde(json);
    });
  }

  @override
  Future<Participante> iniciarSesion({
    required String telefono,
    required PaisTelefono pais,
    required String contrasena,
  }) {
    return _proteger(() async {
      final e164 = UtilesTelefono.aE164(telefono, pais);
      if (e164 == null || contrasena.isEmpty) {
        throw const ErrorReferidos(
          MotivoError.credencialesIncorrectas,
          'Escribe tu celular y tu contraseña.',
        );
      }
      final json = _sinError(await cliente.rpc<dynamic>(
        'cuenta_iniciar_sesion',
        params: {
          'p_telefono': e164,
          'p_contrasena': contrasena,
          'p_huella': await _huellaDispositivo(),
        },
      ));
      await _guardarToken(json);
      return _participanteDesde(json);
    });
  }

  @override
  Future<DesafioVerificacion> reenviarCodigo(String idDesafio) {
    return _proteger(() async {
      final json = await _llamarVerificacion({
        'accion': 'reenviar',
        'id': idDesafio,
      });
      return _desafioDesde(json);
    });
  }

  @override
  Future<Participante> confirmarVerificacion({
    required String idDesafio,
    required String codigo,
  }) {
    return _proteger(() async {
      final json = await _llamarVerificacion({
        'accion': 'confirmar',
        'id': idDesafio,
        'codigo': codigo.trim(),
      });
      await _guardarToken(json);
      return _participanteDesde(json);
    });
  }

  // ---------------------------------------------------------------------
  // Canje de invitaciones sin cuenta ni SMS
  //
  // Funciones publicas de la base: el anclaje del dispositivo y del telefono
  // y todas las reglas anti-fraude se deciden alla.
  // ---------------------------------------------------------------------

  @override
  Future<CodigoAsignado> obtenerCodigoDeEnlace(String tokenEnlace) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'invitado_obtener_codigo',
        params: {
          'p_enlace': tokenEnlace,
          'p_huella': await _huellaDispositivo(),
          'p_dispositivo': (await UtilesDispositivo.leer()).aJson(),
        },
      ));
      return CodigoAsignado(
        codigo: json['codigo'] as String,
        expiraEn: _fecha(json['expira_en']),
        usado: json['usado'] as bool? ?? false,
        nombreInvitador: json['nombre_invitador'] as String?,
      );
    });
  }

  @override
  Future<ResultadoCanje> validarCodigo({
    required String codigoInvitacion,
    required String telefono,
    required PaisTelefono pais,
  }) {
    return _proteger(() async {
      final codigo = _codigoValidado(codigoInvitacion);
      if (codigo == null) {
        throw const ErrorReferidos(
          MotivoError.codigoMalFormado,
          'Escribe el código de invitación que te compartieron.',
        );
      }
      final json = _sinError(await cliente.rpc<dynamic>(
        'invitado_validar_codigo',
        params: {
          'p_codigo': codigo,
          'p_telefono': _telefonoValidado(telefono, pais),
          'p_huella': await _huellaDispositivo(),
          'p_dispositivo': (await UtilesDispositivo.leer()).aJson(),
        },
      ));
      return ResultadoCanje(
        codigo: json['codigo'] as String,
        telefonoE164: json['telefono_e164'] as String,
        validadoEn: _fecha(json['validado_en']),
        nombreInvitador: json['nombre_invitador'] as String?,
      );
    });
  }

  Future<void> _guardarToken(Map<String, dynamic> json) async {
    final token = json['token_sesion'] as String?;
    if (token == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveToken, token);
  }

  /// Llama a la Edge Function de verificacion y devuelve su JSON ya libre de
  /// errores de negocio.
  Future<Map<String, dynamic>> _llamarVerificacion(
    Map<String, dynamic> cuerpo,
  ) async {
    try {
      final respuesta = await cliente.functions.invoke(
        funcionVerificacion,
        body: cuerpo,
      );
      return _sinError(respuesta.data);
    } on FunctionException catch (error) {
      // Respuestas 4xx/5xx: si traen el formato de error de la campana se
      // respeta su mensaje; si no (funcion sin desplegar, caida), se avisa
      // sin mostrar detalles tecnicos.
      final detalles = error.details;
      if (detalles is Map<String, dynamic> && detalles['error'] is Map) {
        _sinError(detalles);
      }
      throw ErrorReferidos(
        MotivoError.servicioSmsNoDisponible,
        error.status == 404
            ? 'La verificación por SMS todavía no está instalada. Despliega '
                'la Edge Function $funcionVerificacion.'
            : 'No pudimos contactar el servicio de verificación. Intenta '
                'de nuevo en unos minutos.',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Invitaciones de un solo uso
  // ---------------------------------------------------------------------

  @override
  Future<InvitacionEmitida> generarInvitacion(String idParticipante) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'sesion_generar_invitacion',
        params: {'p_token': await _tokenObligatorio()},
      ));
      return _invitacionDesde(json);
    });
  }

  @override
  Future<EnlaceInvitacion> miEnlace(String idParticipante) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'sesion_mi_enlace',
        params: {'p_token': await _tokenObligatorio()},
      ));
      return EnlaceInvitacion(
        token: json['token'] as String,
        expiraEn: _fecha(json['expira_en']),
        codigosEntregados: _entero(json['codigos_entregados']),
        maxCodigos: _entero(json['max_codigos']),
      );
    });
  }

  @override
  Future<List<InvitacionEmitida>> misInvitaciones(String idParticipante) {
    return _proteger(() async {
      final filas = await cliente.rpc<dynamic>(
        'sesion_mis_invitaciones',
        params: {'p_token': await _tokenObligatorio()},
      );
      return ((filas as List<dynamic>?) ?? const [])
          .map((f) => _invitacionDesde(f as Map<String, dynamic>))
          .toList();
    });
  }

  // ---------------------------------------------------------------------
  // Panel del participante
  // ---------------------------------------------------------------------

  @override
  Future<List<EventoReferido>> misReferidos(String idParticipante) {
    return _proteger(() async {
      final filas = await cliente.rpc<dynamic>(
        'sesion_mis_referidos',
        params: {'p_token': await _tokenObligatorio()},
      );
      return ((filas as List<dynamic>?) ?? const [])
          .map((f) => _referidoDesde(f as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Participante> refrescarParticipante(String idParticipante) {
    return _proteger(() async {
      final json = await cliente.rpc<dynamic>(
        'sesion_participante',
        params: {'p_token': await _tokenObligatorio()},
      );
      if (json == null) {
        throw const ErrorReferidos(
          MotivoError.noRegistrado,
          'Tu sesión expiró. Vuelve a ingresar.',
        );
      }
      return _participanteDesde(json as Map<String, dynamic>);
    });
  }

  // ---------------------------------------------------------------------
  // Premio: las tres cajas
  // ---------------------------------------------------------------------

  @override
  Future<ReclamoPremio?> miReclamo(String idParticipante) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'sesion_estado_premio',
        params: {'p_token': await _tokenObligatorio()},
      ));
      final reclamo = json['reclamo'];
      return reclamo is Map<String, dynamic> ? _reclamoDesde(reclamo) : null;
    });
  }

  @override
  Future<ReclamoPremio> reclamarPremio(String idParticipante) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'sesion_reclamar_premio',
        params: {'p_token': await _tokenObligatorio()},
      ));
      return _reclamoDesde(json);
    });
  }

  @override
  Future<ReclamoPremio> abrirCaja({
    required String idParticipante,
    required String idReclamo,
    required int caja,
  }) {
    return _proteger(() async {
      final json = _sinError(await cliente.rpc<dynamic>(
        'sesion_abrir_caja',
        params: {
          'p_token': await _tokenObligatorio(),
          'p_reclamo': idReclamo,
          'p_caja': caja,
        },
      ));
      return _reclamoDesde(json);
    });
  }

  // ---------------------------------------------------------------------
  // Validaciones previas
  //
  // Las mismas reglas viven en la base de datos; hacerlas aqui solo evita un
  // viaje de ida y vuelta y da una respuesta inmediata al escribir.
  // ---------------------------------------------------------------------

  String _telefonoValidado(String telefono, PaisTelefono pais) {
    final e164 = UtilesTelefono.aE164(telefono, pais);
    if (e164 == null) {
      throw ErrorReferidos(
        MotivoError.telefonoInvalido,
        pais.mensajeFormatoInvalido,
      );
    }
    if (UtilesTelefono.pareceSospechoso(telefono, pais)) {
      throw const ErrorReferidos(
        MotivoError.numeroSospechoso,
        'Ese número no parece real. Usa tu número personal.',
      );
    }
    return e164;
  }

  String _contrasenaValidada(String contrasena) {
    final error = UtilesCredenciales.errorContrasena(contrasena);
    if (error != null) {
      throw ErrorReferidos(
        MotivoError.contrasenaInvalida,
        'Contraseña no válida: ${error.toLowerCase()}.',
      );
    }
    return contrasena;
  }

  String? _codigoValidado(String? codigoInvitador) {
    if (codigoInvitador == null || codigoInvitador.trim().isEmpty) return null;
    final normalizado = CodigoReferido.normalizar(codigoInvitador);
    if (!CodigoReferido.esValido(normalizado)) {
      throw const ErrorReferidos(
        MotivoError.codigoMalFormado,
        'Ese código de invitación no es válido. Revisa que esté completo.',
      );
    }
    return normalizado;
  }

  // ---------------------------------------------------------------------
  // Conversion de datos
  // ---------------------------------------------------------------------

  static int _entero(Object? valor) =>
      valor is int ? valor : int.tryParse('${valor ?? 0}') ?? 0;

  static DateTime _fecha(Object? valor) =>
      DateTime.tryParse('$valor')?.toLocal() ?? DateTime.now();

  static Participante _participanteDesde(Map<String, dynamic> json) {
    return Participante(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      telefonoE164: json['telefono_e164'] as String,
      codigoInvitador: json['codigo_invitador'] as String?,
      creadoEn: _fecha(json['creado_en']),
      telefonoVerificado: json['telefono_verificado'] as bool? ?? false,
      referidosValidos: _entero(json['referidos_validos']),
      referidosPendientes: _entero(json['referidos_pendientes']),
      ganadorPrueba: json['ganador_prueba'] as bool? ?? false,
    );
  }

  static ReclamoPremio _reclamoDesde(Map<String, dynamic> json) {
    final distribucion = json['distribucion'];
    return ReclamoPremio(
      id: json['id'] as String,
      estado: EstadoReclamo.desdeClave(json['estado'] as String?),
      creadoEn: _fecha(json['creado_en']),
      esPrueba: json['es_prueba'] as bool? ?? false,
      cajaElegida: json['caja_elegida'] == null
          ? null
          : _entero(json['caja_elegida']),
      premio: PremioCaja.desdeClave(json['premio'] as String?),
      codigoConfirmacion: json['codigo_confirmacion'] as String?,
      abiertoEn:
          json['abierto_en'] == null ? null : _fecha(json['abierto_en']),
      distribucion: distribucion is List
          ? [
              for (final clave in distribucion)
                ?PremioCaja.desdeClave('$clave'),
            ]
          : const [],
    );
  }

  static InvitacionEmitida _invitacionDesde(Map<String, dynamic> json) {
    return InvitacionEmitida(
      id: json['id'] as String,
      codigo: json['codigo'] as String,
      creadoEn: _fecha(json['creado_en']),
      expiraEn: _fecha(json['expira_en']),
      usadaEn: json['usada_en'] == null ? null : _fecha(json['usada_en']),
      nombreInvitado: json['nombre_invitado'] as String?,
      destinatario: json['destinatario'] as String?,
      telefonoInvitado: json['telefono_invitado'] as String?,
    );
  }

  static EventoReferido _referidoDesde(Map<String, dynamic> json) {
    return EventoReferido(
      id: json['id'] as String,
      nombreInvitado: json['nombre_invitado'] as String? ?? 'Invitado',
      telefonoInvitado: json['telefono_invitado'] as String? ?? '',
      estado: switch (json['estado']) {
        'valido' => EstadoReferido.valido,
        'rechazado' => EstadoReferido.rechazado,
        _ => EstadoReferido.pendiente,
      },
      creadoEn: _fecha(json['creado_en']),
      motivoRechazo: json['motivo_rechazo'] as String?,
    );
  }

  static DesafioVerificacion _desafioDesde(Map<String, dynamic> json) {
    return DesafioVerificacion(
      id: json['id'] as String,
      telefonoE164: json['telefono_e164'] as String,
      expiraEn: _fecha(json['expira_en']),
    );
  }

  // ---------------------------------------------------------------------
  // Errores
  // ---------------------------------------------------------------------

  /// Convierte en excepcion el error que las funciones de la campana
  /// devuelven como dato.
  ///
  /// La base NO lanza `raise exception` para las reglas de negocio: una
  /// excepcion abortaria la transaccion y se perderian el contador de
  /// intentos fallidos y los eventos de auditoria escritos un instante
  /// antes. Por eso el error viaja dentro del propio JSON, y es aqui donde
  /// vuelve a ser un [ErrorReferidos] como espera el resto de la aplicacion.
  static Map<String, dynamic> _sinError(Object? respuesta) {
    if (respuesta is! Map<String, dynamic>) {
      throw const ErrorReferidos(
        MotivoError.desconocido,
        'Algo falló de nuestro lado. Intenta de nuevo.',
      );
    }
    final json = respuesta;
    final error = json['error'];
    if (error is Map) {
      final motivo = MotivoError.values.firstWhere(
        (m) => m.name == error['motivo'],
        orElse: () => MotivoError.desconocido,
      );
      throw ErrorReferidos(
        motivo,
        error['mensaje'] as String? ?? 'Algo falló de nuestro lado.',
      );
    }
    return json;
  }

  /// Traduce al vocabulario del dominio los errores que si llegan como
  /// excepcion: violaciones de restricciones y triggers de la base.
  static Future<T> _proteger<T>(Future<T> Function() operacion) async {
    try {
      return await operacion();
    } on ErrorReferidos {
      rethrow;
    } on PostgrestException catch (error) {
      throw errorDesdeMensaje(error.message);
    }
  }

  static ErrorReferidos errorDesdeMensaje(String mensaje) {
    final marca = mensaje.indexOf('ONX:');
    if (marca >= 0) {
      final partes = mensaje.substring(marca + 4).split(':');
      if (partes.length >= 2) {
        final motivo = MotivoError.values.firstWhere(
          (m) => m.name == partes.first.trim(),
          orElse: () => MotivoError.desconocido,
        );
        return ErrorReferidos(motivo, partes.sublist(1).join(':').trim());
      }
    }

    // Red de seguridad: si salta una restriccion de la base directamente.
    final texto = mensaje.toLowerCase();
    if (texto.contains('telefono_e164') && texto.contains('duplicate')) {
      return const ErrorReferidos(
        MotivoError.telefonoYaRegistrado,
        'Este número ya está participando.',
      );
    }
    if (texto.contains('circular')) {
      return const ErrorReferidos(
        MotivoError.referidoCircular,
        'Esa cadena de invitaciones no es válida.',
      );
    }
    if (texto.contains('schema cache') ||
        texto.contains('does not exist') ||
        texto.contains('could not find')) {
      return const ErrorReferidos(
        MotivoError.desconocido,
        'A la base de datos le falta el esquema de la campaña. Ejecuta '
        'docs/esquema_supabase_completo.sql en el editor SQL de Supabase.',
      );
    }
    return ErrorReferidos(MotivoError.desconocido, mensaje);
  }
}

/// Comprueba que el esquema de la campana este aplicado en el proyecto.
///
/// Se llama al arrancar: si la base todavia esta vacia es mucho mejor caer al
/// modo memoria y decirlo, que mostrar una landing con todos los contadores
/// en cero y sin explicacion. Devuelve el motivo del problema, o `null` si
/// todo esta en su sitio.
Future<String?> revisarEsquema(SupabaseClient cliente) async {
  const tokenVacio = '00000000-0000-0000-0000-000000000000';
  try {
    await cliente.from('vista_ranking').select().limit(1);
    await cliente.rpc<dynamic>(
      'sesion_participante',
      params: {'p_token': tokenVacio},
    );
    // Si falta la parte del premio, esta llamada es la que falla.
    await cliente.rpc<dynamic>(
      'sesion_estado_premio',
      params: {'p_token': tokenVacio},
    );
    return null;
  } on PostgrestException catch (error) {
    return 'El proyecto Supabase responde, pero le falta el esquema de '
        '${ConfigCampana.nombreCampana}. Ejecuta '
        'docs/esquema_supabase_completo.sql en el editor SQL. '
        '(${error.message})';
  } catch (error) {
    return 'No se pudo conectar con Supabase: $error';
  }
}
