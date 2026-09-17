import 'package:flutter/foundation.dart';

import '../nucleo/config_campana.dart';
import '../utiles/codigo_referido.dart';
import '../utiles/telefono.dart';
import 'modelos.dart';
import 'repositorio_memoria.dart';
import 'repositorio_referidos.dart';

/// Etapa del formulario de participacion (crear cuenta para invitar).
enum EtapaRegistro { datos, verificacion, listo }

/// Etapa de la validacion de un codigo de invitacion (sin cuenta ni SMS).
enum EtapaCanje { datos, listo }

/// Estado compartido de la campana.
///
/// Es el unico punto que habla con [RepositorioReferidos]; las pantallas solo
/// leen sus propiedades y llaman a sus metodos. Cuando entre Supabase, basta
/// con inyectar otro repositorio en el constructor.
class ControladorReferidos extends ChangeNotifier {
  ControladorReferidos(this._repositorio);

  final RepositorioReferidos _repositorio;

  Participante? participante;
  List<EventoReferido> misReferidos = const [];
  List<InvitacionEmitida> misInvitaciones = const [];

  /// Reclamo del premio vigente, o `null` si todavia no reclamo.
  ReclamoPremio? reclamo;

  /// Mientras se espera la respuesta del servidor al abrir una caja.
  bool abriendoCaja = false;

  bool cargandoInicial = true;
  bool procesando = false;
  String? mensajeError;

  EtapaRegistro etapa = EtapaRegistro.datos;
  DesafioVerificacion? desafio;

  EtapaCanje etapaCanje = EtapaCanje.datos;
  ResultadoCanje? resultadoCanje;

  /// Link de invitacion de quien tiene la sesion abierta. Se carga con el
  /// panel para que «Compartir link» abra WhatsApp sin esperas: los
  /// navegadores de celular bloquean la ventana si se abre tarde.
  EnlaceInvitacion? enlace;

  /// Codigo recien generado a mano para una persona.
  InvitacionEmitida? ultimaInvitacion;

  /// Codigo de invitacion detectado en la URL (`?ref=ONX-XXXX-XXXX`).
  String? codigoInvitadorDetectado;

  /// Link de invitacion detectado en la URL (`?inv=XXXXXXXXXX`).
  String? tokenEnlaceDetectado;

  /// Codigo que el link entrego a este dispositivo.
  CodigoAsignado? codigoAsignado;
  bool cargandoCodigoAsignado = false;

  /// Por que el link no pudo entregar un codigo (vencido, propio...).
  String? errorEnlace;

  bool get haySesion => participante != null;

  bool get modoDemostracion => _repositorio is RepositorioDemostrable;

  String get _origen {
    final base = Uri.base;
    // Solo el dominio: los links siempre apuntan al inicio, aunque se
    // copien desde otra pantalla (/premios, /onix-drive...).
    final esWeb = base.scheme == 'http' || base.scheme == 'https';
    return esWeb && base.hasAuthority
        ? '${base.scheme}://${base.authority}'
        : ConfigCampana.origenPorDefecto;
  }

  /// Link con un codigo individual. Usa el origen real del navegador cuando
  /// esta disponible para que funcione igual en local y en produccion.
  String linkDeInvitacion(String codigo) =>
      '$_origen/?ref=${CodigoReferido.paraMostrar(codigo)}';

  /// Link de invitacion para compartir con muchos contactos a la vez.
  String linkDelEnlace(EnlaceInvitacion enlace) =>
      '$_origen/?inv=${enlace.token}';

  /// Mensaje para WhatsApp con el link de invitacion. WhatsApp manda este
  /// mismo texto a todos los contactos elegidos; el codigo de cada uno se
  /// genera cuando abre el link.
  String mensajeDelEnlace(Participante quien, EnlaceInvitacion enlace) {
    return '¡Hola! Soy ${quien.primerNombre}. Me estoy moviendo con '
        '${ConfigCampana.nombreMarca} y hay premios por invitar.\n\n'
        'Abre este link desde tu celular: te da un código exclusivo para ti '
        'y lo validas solo con tu número, sin crear cuenta.\n'
        '${linkDelEnlace(enlace)}';
  }

  /// Mensaje con un codigo individual, para una sola persona.
  String mensajeDeInvitacion(Participante quien, InvitacionEmitida invitacion) {
    final link = linkDeInvitacion(invitacion.codigo);
    return '¡Hola! Soy ${quien.primerNombre}. Me estoy moviendo con '
        '${ConfigCampana.nombreMarca} y hay premios por invitar.\n\n'
        'Este código es exclusivo para ti: ${invitacion.codigoVisible}\n'
        'Valídalo aquí con tu número (no necesitas crear cuenta):\n$link';
  }

  /// Abre WhatsApp con [mensaje] sin destinatario: en el celular se elige a
  /// uno o varios contactos en la lista de WhatsApp.
  static Uri enlaceWhatsApp(String mensaje) =>
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(mensaje)}');

  Future<void> inicializar() async {
    _leerCodigoDeLaUrl();
    try {
      participante = await _repositorio.sesionActual();
      if (participante != null) {
        etapa = EtapaRegistro.listo;
        await _recargarPanel();
      } else if (tokenEnlaceDetectado != null) {
        await _cargarCodigoAsignado();
      }
    } on ErrorReferidos catch (error) {
      mensajeError = error.mensaje;
    } finally {
      cargandoInicial = false;
      notifyListeners();
    }
  }

  void _leerCodigoDeLaUrl() {
    final token = Uri.base.queryParameters['inv'];
    if (token != null) {
      tokenEnlaceDetectado = CodigoReferido.normalizarToken(token);
    }
    final crudo = Uri.base.queryParameters['ref'] ??
        Uri.base.queryParameters['r'] ??
        Uri.base.fragment.split('ref=').skip(1).join();
    if (crudo.isEmpty) return;
    final normalizado = CodigoReferido.normalizar(crudo);
    if (CodigoReferido.esValido(normalizado)) {
      codigoInvitadorDetectado = normalizado;
    }
  }

  /// Pide al servidor el codigo que el link entrega a este dispositivo.
  Future<void> _cargarCodigoAsignado() async {
    final token = tokenEnlaceDetectado;
    if (token == null) return;
    cargandoCodigoAsignado = true;
    errorEnlace = null;
    notifyListeners();
    try {
      codigoAsignado = await _repositorio.obtenerCodigoDeEnlace(token);
    } on ErrorReferidos catch (error) {
      errorEnlace = error.mensaje;
    } catch (_) {
      errorEnlace = 'No pudimos cargar tu código. Revisa tu conexión y vuelve '
          'a abrir el link.';
    } finally {
      cargandoCodigoAsignado = false;
      notifyListeners();
    }
  }

  Future<void> reintentarCodigoAsignado() => _cargarCodigoAsignado();

  void limpiarError() {
    if (mensajeError == null) return;
    mensajeError = null;
    notifyListeners();
  }

  void volverADatos() {
    etapa = EtapaRegistro.datos;
    desafio = null;
    mensajeError = null;
    notifyListeners();
  }

  /// Paso 1 del registro: valida los datos de la cuenta y envia el codigo
  /// de verificacion por SMS al telefono.
  Future<bool> registrar({
    required String nombre,
    required String contrasena,
    required String telefono,
    required PaisTelefono pais,
  }) {
    return _ejecutar(() async {
      desafio = await _repositorio.iniciarRegistro(
        nombre: nombre,
        contrasena: contrasena,
        telefono: telefono,
        pais: pais,
      );
      etapa = EtapaRegistro.verificacion;
    });
  }

  /// Ingreso de quien ya tiene cuenta: celular y contrasena, sin SMS.
  Future<bool> ingresar({
    required String telefono,
    required PaisTelefono pais,
    required String contrasena,
  }) {
    return _ejecutar(() async {
      participante = await _repositorio.iniciarSesion(
        telefono: telefono,
        pais: pais,
        contrasena: contrasena,
      );
      desafio = null;
      etapa = EtapaRegistro.listo;
      await _recargarPanel();
    });
  }

  /// Paso 2 del registro: confirmar el codigo recibido y crear la cuenta.
  Future<bool> confirmarCodigo(String codigo) {
    return _ejecutar(() async {
      final actual = desafio;
      if (actual == null) {
        throw const ErrorReferidos(
          MotivoError.verificacionExpirada,
          'La verificación expiró. Vuelve a empezar.',
        );
      }
      participante = await _repositorio.confirmarVerificacion(
        idDesafio: actual.id,
        codigo: codigo,
      );
      desafio = null;
      etapa = EtapaRegistro.listo;
      await _recargarPanel();
    });
  }

  Future<bool> reenviarCodigo() {
    return _ejecutar(() async {
      final actual = desafio;
      if (actual == null) return;
      desafio = await _repositorio.reenviarCodigo(actual.id);
    });
  }

  /// Quien fue invitado valida su codigo con su celular, sin cuenta ni
  /// SMS: el codigo queda anclado a su telefono y a su dispositivo.
  Future<bool> validarCodigo({
    required String codigoInvitacion,
    required String telefono,
    required PaisTelefono pais,
  }) {
    return _ejecutar(() async {
      resultadoCanje = await _repositorio.validarCodigo(
        codigoInvitacion: codigoInvitacion,
        telefono: telefono,
        pais: pais,
      );
      etapaCanje = EtapaCanje.listo;
    });
  }

  Future<void> refrescar() async {
    if (participante == null) return;
    await _ejecutar(() async {
      participante = await _repositorio.refrescarParticipante(participante!.id);
      await _recargarPanel();
    });
  }

  /// Genera un codigo individual, de un solo uso, para una persona.
  Future<bool> generarInvitacion() {
    return _ejecutar(() async {
      if (participante == null) return;
      final invitacion = await _repositorio.generarInvitacion(
        participante!.id,
      );
      ultimaInvitacion = invitacion;
      misInvitaciones = [invitacion, ...misInvitaciones];
    });
  }

  /// Vuelve a pedir el link de invitacion (por si el anterior se lleno o
  /// esta por vencer). Con [silencioso] un fallo no muestra ningun aviso:
  /// se usa para las renovaciones automaticas en segundo plano.
  Future<void> actualizarEnlace({bool silencioso = false}) async {
    if (participante == null) return;
    try {
      enlace = await _repositorio.miEnlace(participante!.id);
      notifyListeners();
    } on ErrorReferidos catch (error) {
      if (silencioso) return;
      mensajeError = error.mensaje;
      notifyListeners();
    } catch (_) {
      if (silencioso) return;
      mensajeError = 'No pudimos cargar tu link. Revisa tu conexión e intenta '
          'de nuevo.';
      notifyListeners();
    }
  }

  /// «Reclamar premio»: deja listas las tres cajas cerradas. El orden de
  /// los premios lo decide el servidor y no llega aqui hasta abrir una.
  Future<bool> reclamarPremio() {
    return _ejecutar(() async {
      if (participante == null) return;
      reclamo = await _repositorio.reclamarPremio(participante!.id);
    });
  }

  /// Abre la caja [caja] (0, 1 o 2) del reclamo vigente. Devuelve el
  /// reclamo ya abierto, con el premio y la distribucion, o `null` si fallo.
  Future<ReclamoPremio?> abrirCaja(int caja) async {
    final actual = reclamo;
    if (participante == null || actual == null || abriendoCaja) return null;
    abriendoCaja = true;
    mensajeError = null;
    notifyListeners();
    try {
      reclamo = await _repositorio.abrirCaja(
        idParticipante: participante!.id,
        idReclamo: actual.id,
        caja: caja,
      );
      return reclamo;
    } on ErrorReferidos catch (error) {
      mensajeError = error.mensaje;
      return null;
    } catch (_) {
      mensajeError = 'No pudimos abrir la caja. Revisa tu conexión e intenta '
          'de nuevo.';
      return null;
    } finally {
      abriendoCaja = false;
      notifyListeners();
    }
  }

  /// Solo disponible con el repositorio de demostracion: agrega invitados
  /// ficticios para poder mostrar el recorrido completo sin backend.
  Future<void> simularInvitados(int cantidad) async {
    if (_repositorio is! RepositorioDemostrable) return;
    if (participante == null) return;
    final demo = _repositorio as RepositorioDemostrable;
    await _ejecutar(() async {
      await demo.simularInvitados(participante!.id, cantidad);
      participante = await _repositorio.refrescarParticipante(participante!.id);
      await _recargarPanel();
    });
  }

  /// Solo demostracion: descarta el premio para volver a elegir caja.
  Future<void> reiniciarPremioDemo() async {
    if (_repositorio is! RepositorioDemostrable) return;
    if (participante == null) return;
    final demo = _repositorio as RepositorioDemostrable;
    await _ejecutar(() async {
      await demo.reiniciarPremio(participante!.id);
      reclamo = null;
    });
  }

  Future<void> cerrarSesion() async {
    await _repositorio.cerrarSesion();
    participante = null;
    misReferidos = const [];
    misInvitaciones = const [];
    ultimaInvitacion = null;
    enlace = null;
    reclamo = null;
    desafio = null;
    etapa = EtapaRegistro.datos;
    notifyListeners();
  }

  Future<void> _recargarPanel() async {
    if (participante == null) return;
    final id = participante!.id;
    final resultados = await Future.wait<Object?>([
      _repositorio.misReferidos(id),
      _repositorio.misInvitaciones(id),
      _repositorio.miReclamo(id),
      _repositorio.miEnlace(id),
    ]);
    misReferidos = resultados[0] as List<EventoReferido>;
    misInvitaciones = resultados[1] as List<InvitacionEmitida>;
    reclamo = resultados[2] as ReclamoPremio?;
    enlace = resultados[3] as EnlaceInvitacion;
  }

  /// Envuelve una operacion con el manejo comun de carga y errores.
  Future<bool> _ejecutar(Future<void> Function() operacion) async {
    procesando = true;
    mensajeError = null;
    notifyListeners();
    try {
      await operacion();
      return true;
    } on ErrorReferidos catch (error) {
      mensajeError = error.mensaje;
      return false;
    } catch (_) {
      mensajeError = 'Algo falló de nuestro lado. Intenta de nuevo.';
      return false;
    } finally {
      procesando = false;
      notifyListeners();
    }
  }
}
