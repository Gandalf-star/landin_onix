import 'package:flutter/foundation.dart';

import '../nucleo/config_campana.dart';
import '../utiles/codigo_referido.dart';
import '../utiles/telefono.dart';
import 'modelos.dart';
import 'repositorio_memoria.dart';
import 'repositorio_referidos.dart';

/// Etapa del formulario de participacion.
enum EtapaRegistro { datos, verificacion, listo }

/// Estado compartido de la campana.
///
/// Es el unico punto que habla con [RepositorioReferidos]; las pantallas solo
/// leen sus propiedades y llaman a sus metodos. Cuando entre Supabase, basta
/// con inyectar otro repositorio en el constructor.
class ControladorReferidos extends ChangeNotifier {
  ControladorReferidos(this._repositorio);

  final RepositorioReferidos _repositorio;

  List<FilaRanking> ranking = const [];
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

  /// Codigo de invitacion detectado en la URL (`?ref=ONX-XXXX-XXXX`).
  String? codigoInvitadorDetectado;

  bool get haySesion => participante != null;

  bool get modoDemostracion => _repositorio is RepositorioDemostrable;

  /// Link personal para compartir. Usa el origen real del navegador cuando
  /// esta disponible para que funcione igual en local y en produccion.
  String linkDeInvitacion(String codigo) {
    final base = Uri.base;
    final origen = base.hasAuthority
        ? '${base.scheme}://${base.authority}${base.path}'
        : ConfigCampana.origenPorDefecto;
    final limpio = origen.endsWith('/')
        ? origen.substring(0, origen.length - 1)
        : origen;
    return '$limpio/?ref=${CodigoReferido.paraMostrar(codigo)}';
  }

  /// Mensaje listo para WhatsApp con un codigo de invitacion concreto: es de
  /// un solo uso, asi que hay que generar uno nuevo por cada persona.
  String mensajeDeInvitacion(Participante quien, InvitacionEmitida invitacion) {
    final link = linkDeInvitacion(invitacion.codigo);
    return '¡Hola! Soy ${quien.primerNombre}. Me estoy moviendo con '
        '${ConfigCampana.nombreMarca} y hay premios por invitar.\n\n'
        'Este código es exclusivo para ti: ${invitacion.codigoVisible}\n'
        'Regístrate aquí y participa tú también:\n$link';
  }

  Future<void> inicializar() async {
    _leerCodigoDeLaUrl();
    try {
      participante = await _repositorio.sesionActual();
      ranking = await _repositorio.obtenerRanking(
        idParticipante: participante?.id,
      );
      if (participante != null) {
        etapa = EtapaRegistro.listo;
        await _recargarPanel();
      }
    } on ErrorReferidos catch (error) {
      mensajeError = error.mensaje;
    } finally {
      cargandoInicial = false;
      notifyListeners();
    }
  }

  void _leerCodigoDeLaUrl() {
    final crudo = Uri.base.queryParameters['ref'] ??
        Uri.base.queryParameters['r'] ??
        Uri.base.fragment.split('ref=').skip(1).join();
    if (crudo.isEmpty) return;
    final normalizado = CodigoReferido.normalizar(crudo);
    if (CodigoReferido.esValido(normalizado)) {
      codigoInvitadorDetectado = normalizado;
    }
  }

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
    String? codigoInvitador,
  }) {
    return _ejecutar(() async {
      desafio = await _repositorio.iniciarRegistro(
        nombre: nombre,
        contrasena: contrasena,
        telefono: telefono,
        pais: pais,
        codigoInvitador: codigoInvitador,
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

  Future<void> refrescar() async {
    if (participante == null) return;
    await _ejecutar(() async {
      participante = await _repositorio.refrescarParticipante(participante!.id);
      await _recargarPanel();
    });
  }

  /// Genera un codigo de invitacion nuevo, de un solo uso, listo para
  /// compartir con la proxima persona que se quiera invitar por WhatsApp.
  Future<bool> generarInvitacion() {
    return _ejecutar(() async {
      if (participante == null) return;
      final invitacion = await _repositorio.generarInvitacion(
        participante!.id,
      );
      misInvitaciones = [invitacion, ...misInvitaciones];
    });
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
    reclamo = null;
    desafio = null;
    etapa = EtapaRegistro.datos;
    ranking = await _repositorio.obtenerRanking();
    notifyListeners();
  }

  Future<void> _recargarPanel() async {
    if (participante == null) return;
    final id = participante!.id;
    final resultados = await Future.wait<Object?>([
      _repositorio.misReferidos(id),
      _repositorio.misInvitaciones(id),
      _repositorio.miReclamo(id),
      _repositorio.obtenerRanking(idParticipante: id),
    ]);
    misReferidos = resultados[0] as List<EventoReferido>;
    misInvitaciones = resultados[1] as List<InvitacionEmitida>;
    reclamo = resultados[2] as ReclamoPremio?;
    ranking = resultados[3] as List<FilaRanking>;
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
