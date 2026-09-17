import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../datos/controlador_referidos.dart';
import '../../datos/modelos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../../utiles/codigo_referido.dart';
import '../../utiles/credenciales.dart';
import '../../utiles/telefono.dart';
import '../componentes/botones.dart';
import 'campo_codigo.dart';

/// Lo que viene a hacer la persona a la tarjeta del hero.
enum _Modo {
  /// Recibio un codigo: lo valida con su celular, sin crear cuenta.
  canje,

  /// Quiere invitar: crea su cuenta (o ingresa, si ya la tiene).
  registro,
  ingreso,
}

/// Tarjeta blanca del hero con los dos caminos de la campana.
///
/// - «Tengo un código»: codigo (el link lo entrega solo) + celular -> la
///   invitacion suma. Sin cuenta ni SMS.
/// - «Quiero invitar»: datos de la cuenta -> SMS -> panel. Quien ya tiene
///   cuenta entra con su celular y su contrasena, sin SMS.
class TarjetaParticipacion extends StatefulWidget {
  const TarjetaParticipacion({super.key});

  @override
  State<TarjetaParticipacion> createState() => _TarjetaParticipacionState();
}

class _TarjetaParticipacionState extends State<TarjetaParticipacion> {
  final _formulario = GlobalKey<FormState>();
  final _formularioCanje = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _contrasena = TextEditingController();
  final _telefono = TextEditingController();
  final _codigoInvitacion = TextEditingController();
  final _telefonoCanje = TextEditingController();
  final _codigoVerificacion = TextEditingController();

  _Modo _modo = _Modo.registro;
  bool _verContrasena = false;
  bool _aceptaBases = false;
  bool _aceptaBasesCanje = false;

  /// El codigo vino del link (bloqueado) y no se escribio a mano.
  bool _codigoVieneDeLink = false;
  String? _codigoAsignadoMostrado;
  PaisTelefono _pais = PaisTelefono.chile;
  PaisTelefono _paisCanje = PaisTelefono.chile;

  bool get _modoIngreso => _modo == _Modo.ingreso;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controlador = ProveedorCampana.accion(context);
      final detectado = controlador.codigoInvitadorDetectado;
      if (controlador.tokenEnlaceDetectado != null) {
        // Llego por un link de invitacion: su codigo se genera solo.
        setState(() => _modo = _Modo.canje);
      } else if (detectado != null) {
        // Llego con un codigo individual en el link.
        setState(() {
          _codigoInvitacion.text = CodigoReferido.paraMostrar(detectado);
          _codigoVieneDeLink = true;
          _modo = _Modo.canje;
        });
      }
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _contrasena.dispose();
    _telefono.dispose();
    _codigoInvitacion.dispose();
    _telefonoCanje.dispose();
    _codigoVerificacion.dispose();
    super.dispose();
  }

  void _cambiarModo(_Modo nuevo) {
    if (nuevo == _modo) return;
    ProveedorCampana.accion(context).limpiarError();
    setState(() {
      _modo = nuevo;
      _contrasena.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);

    // El codigo que entrego el link se escribe solo, una vez.
    final asignado = controlador.codigoAsignado;
    if (asignado != null && _codigoAsignadoMostrado != asignado.codigo) {
      _codigoAsignadoMostrado = asignado.codigo;
      _codigoInvitacion.text = asignado.codigoVisible;
      _codigoVieneDeLink = true;
    }

    final Widget contenido;
    if (_modo == _Modo.canje) {
      contenido = controlador.etapaCanje == EtapaCanje.listo
          ? _CanjeListo(
              resultado: controlador.resultadoCanje,
              alQuererInvitar: () => _cambiarModo(_Modo.registro),
            )
          : _construirPasoCanje(context, controlador);
    } else if (controlador.etapa == EtapaRegistro.verificacion) {
      contenido = _PasoVerificacion(
        controladorCodigo: _codigoVerificacion,
        alVolver: () {
          _codigoVerificacion.clear();
          controlador.volverADatos();
        },
      );
    } else {
      contenido = _construirPasoDatos(context, controlador);
    }

    // El selector solo se muestra mientras se llenan los datos: en medio de
    // una verificacion por SMS no tiene sentido cambiar de camino.
    final enDatos = _modo == _Modo.canje
        ? controlador.etapaCanje == EtapaCanje.datos
        : controlador.etapa == EtapaRegistro.datos;

    return Container(
      padding: EdgeInsets.all(
        PuntosQuiebre.esMovilChico(context)
            ? 20
            : (PuntosQuiebre.esMovil(context) ? 24 : 28),
      ),
      decoration: BoxDecoration(
        color: ColoresOnix.blanco,
        borderRadius: BorderRadius.circular(MedidasOnix.radioExtra),
        border: Border.all(color: ColoresOnix.blanco.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enDatos) ...[
              _SelectorCamino(
                canje: _modo == _Modo.canje,
                alElegir: (canje) =>
                    _cambiarModo(canje ? _Modo.canje : _Modo.registro),
              ),
              const SizedBox(height: 22),
            ],
            contenido,
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tengo un codigo
  // ---------------------------------------------------------------------

  Widget _construirPasoCanje(
    BuildContext context,
    ControladorReferidos controlador,
  ) {
    final porLink = controlador.tokenEnlaceDetectado != null;
    final asignado = controlador.codigoAsignado;

    return Form(
      key: _formularioCanje,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Valida tu invitación',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 8),
          Text(
            porLink
                ? 'Este link te da un código exclusivo. Escribe tu celular y '
                    'valídalo: sin cuentas, contraseñas ni SMS.'
                : 'Escribe el código que te compartieron y tu celular. Sin '
                    'cuentas, contraseñas ni SMS.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: ColoresOnix.textoSuave),
          ),
          const SizedBox(height: 22),
          if (porLink && controlador.cargandoCodigoAsignado) ...[
            const _AvisoCargandoCodigo(),
            const SizedBox(height: 18),
          ] else if (porLink && controlador.errorEnlace != null) ...[
            _AvisoEnlaceFallido(
              texto: controlador.errorEnlace!,
              alReintentar: controlador.reintentarCodigoAsignado,
            ),
            const SizedBox(height: 18),
          ] else if (asignado != null) ...[
            _AvisoInvitacion(
              nombreInvitador: asignado.nombreInvitador,
              yaUsado: asignado.usado,
            ),
            const SizedBox(height: 18),
          ] else if (_codigoVieneDeLink) ...[
            const _AvisoInvitacion(),
            const SizedBox(height: 18),
          ],
          const _Etiqueta('Código de invitación'),
          TextFormField(
            key: const ValueKey('campo_codigo_invitacion'),
            controller: _codigoInvitacion,
            readOnly: _codigoVieneDeLink,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'ONX-XXXX-XXXX',
              prefixIcon:
                  const Icon(Icons.confirmation_number_rounded, size: 20),
              suffixIcon: _codigoVieneDeLink
                  ? const Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: ColoresOnix.verde,
                    )
                  : null,
            ),
            validator: (valor) {
              final texto = (valor ?? '').trim();
              if (texto.isEmpty) {
                return 'Escribe el código que te compartieron';
              }
              return CodigoReferido.esValido(CodigoReferido.normalizar(texto))
                  ? null
                  : 'Ese código no es válido. Revisa que esté completo';
            },
          ),
          const SizedBox(height: 16),
          const _Etiqueta('Tu celular'),
          _CampoTelefono(
            controlador: _telefonoCanje,
            pais: _paisCanje,
            alCambiarPais: (nuevo) => setState(() {
              _paisCanje = nuevo;
              _telefonoCanje.clear();
            }),
          ),
          const SizedBox(height: 18),
          _CasillaBases(
            valor: _aceptaBasesCanje,
            texto: 'Acepto las bases del ${ConfigCampana.nombreCampana}. Mi '
                'número y este dispositivo quedarán asociados a este código y '
                'no podrán validar otra invitación.',
            alCambiar: (valor) => setState(() => _aceptaBasesCanje = valor),
          ),
          if (controlador.mensajeError != null) ...[
            const SizedBox(height: 18),
            _MensajeError(texto: controlador.mensajeError!),
          ],
          const SizedBox(height: 22),
          BotonDorado(
            texto: 'Validar código',
            icono: Icons.verified_rounded,
            expandido: true,
            cargando: controlador.procesando,
            alPresionar: controlador.cargandoCodigoAsignado
                ? null
                : () => _enviarCanje(controlador),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarCanje(ControladorReferidos controlador) async {
    if (controlador.procesando) return;
    if (!(_formularioCanje.currentState?.validate() ?? false)) return;
    if (!_aceptaBasesCanje) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar las bases para validar tu código.'),
        ),
      );
      return;
    }
    await controlador.validarCodigo(
      codigoInvitacion: _codigoInvitacion.text,
      telefono: _telefonoCanje.text,
      pais: _paisCanje,
    );
  }

  // ---------------------------------------------------------------------
  // Quiero invitar: crear cuenta o ingresar
  // ---------------------------------------------------------------------

  Widget _construirPasoDatos(
    BuildContext context,
    ControladorReferidos controlador,
  ) {
    return Form(
      key: _formulario,
      // Deja que el navegador ofrezca guardar y autocompletar la cuenta.
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _modoIngreso ? 'Ingresa a tu cuenta' : 'Participa gratis',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 8),
            Text(
              _modoIngreso
                  ? 'Entra con tu celular y tu contraseña para ver tu '
                      'progreso.'
                  : 'Crea tu cuenta para generar códigos e invitar a tus '
                      'contactos. Confirmaremos tu celular con un código por '
                      'SMS.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: ColoresOnix.textoSuave),
            ),
            const SizedBox(height: 24),

            if (!_modoIngreso) ...[
              const _Etiqueta('Tu nombre'),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration:
                    const InputDecoration(hintText: 'Nombre y apellido'),
                validator: (valor) => (valor ?? '').trim().length < 3
                    ? 'Escribe tu nombre completo'
                    : null,
              ),
              const SizedBox(height: 16),
            ],

            const _Etiqueta('Tu celular'),
            _CampoTelefono(
              controlador: _telefono,
              pais: _pais,
              alCambiarPais: (nuevo) => setState(() {
                _pais = nuevo;
                _telefono.clear();
              }),
            ),
            const SizedBox(height: 16),

            const _Etiqueta('Contraseña'),
            TextFormField(
              controller: _contrasena,
              obscureText: !_verContrasena,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _modoIngreso
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              decoration: InputDecoration(
                hintText: _modoIngreso
                    ? 'Tu contraseña'
                    : 'Mínimo 8, con letras y números',
                suffixIcon: IconButton(
                  tooltip: _verContrasena
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  icon: Icon(
                    _verContrasena
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 19,
                  ),
                  onPressed: () =>
                      setState(() => _verContrasena = !_verContrasena),
                ),
              ),
              validator: (valor) => _modoIngreso
                  ? ((valor ?? '').isEmpty ? 'Escribe tu contraseña' : null)
                  : UtilesCredenciales.errorContrasena(valor ?? ''),
              onFieldSubmitted: _modoIngreso ? (_) => _enviar(controlador) : null,
            ),

            if (!_modoIngreso) ...[
              const SizedBox(height: 18),
              _CasillaBases(
                valor: _aceptaBases,
                texto: 'Acepto las bases del ${ConfigCampana.nombreCampana} '
                    'y que me envíen un SMS para verificar mi número.',
                alCambiar: (valor) => setState(() => _aceptaBases = valor),
              ),
            ],

            if (controlador.mensajeError != null) ...[
              const SizedBox(height: 18),
              _MensajeError(texto: controlador.mensajeError!),
            ],

            const SizedBox(height: 22),
            BotonDorado(
              texto: _modoIngreso ? 'Ingresar' : 'Crear mi cuenta',
              icono: _modoIngreso
                  ? Icons.login_rounded
                  : Icons.rocket_launch_rounded,
              expandido: true,
              cargando: controlador.procesando,
              alPresionar: () => _enviar(controlador),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  _formulario.currentState?.reset();
                  _cambiarModo(_modoIngreso ? _Modo.registro : _Modo.ingreso);
                },
                child: Text(
                  _modoIngreso
                      ? '¿Aún no tienes cuenta? Regístrate'
                      : 'Ya tengo cuenta · Ingresar',
                  style: const TextStyle(
                    color: ColoresOnix.azulElectrico,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviar(ControladorReferidos controlador) async {
    if (controlador.procesando) return;
    if (!(_formulario.currentState?.validate() ?? false)) return;

    if (_modoIngreso) {
      final exito = await controlador.ingresar(
        telefono: _telefono.text,
        pais: _pais,
        contrasena: _contrasena.text,
      );
      if (exito) TextInput.finishAutofillContext();
      return;
    }

    if (!_aceptaBases) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar las bases para participar.'),
        ),
      );
      return;
    }

    await controlador.registrar(
      nombre: _nombre.text,
      contrasena: _contrasena.text,
      telefono: _telefono.text,
      pais: _pais,
    );
  }
}

/// Dos pestañas: validar un codigo recibido o crear cuenta para invitar.
class _SelectorCamino extends StatelessWidget {
  const _SelectorCamino({required this.canje, required this.alElegir});

  final bool canje;
  final ValueChanged<bool> alElegir;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ColoresOnix.fondo,
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        border: Border.all(color: ColoresOnix.borde),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PestanaCamino(
              texto: 'Tengo un código',
              icono: Icons.confirmation_number_rounded,
              activa: canje,
              alTocar: () => alElegir(true),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PestanaCamino(
              texto: 'Quiero invitar',
              icono: Icons.group_add_rounded,
              activa: !canje,
              alTocar: () => alElegir(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _PestanaCamino extends StatelessWidget {
  const _PestanaCamino({
    required this.texto,
    required this.icono,
    required this.activa,
    required this.alTocar,
  });

  final String texto;
  final IconData icono;
  final bool activa;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = activa ? ColoresOnix.amarilloOnix : ColoresOnix.textoSuave;
    return Semantics(
      button: true,
      selected: activa,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            decoration: BoxDecoration(
              color: activa ? ColoresOnix.azulOnix : Colors.transparent,
              borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, size: 17, color: color),
                  const SizedBox(width: 7),
                  Text(
                    texto,
                    maxLines: 1,
                    style: TextStyle(
                      color: activa ? ColoresOnix.blanco : ColoresOnix.texto,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Celular con selector de pais, igual en los dos caminos.
class _CampoTelefono extends StatelessWidget {
  const _CampoTelefono({
    required this.controlador,
    required this.pais,
    required this.alCambiarPais,
  });

  final TextEditingController controlador;
  final PaisTelefono pais;
  final ValueChanged<PaisTelefono> alCambiarPais;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(pais),
      controller: controlador,
      keyboardType: TextInputType.phone,
      inputFormatters: [FormateadorTelefono(pais: pais)],
      autofillHints: const [AutofillHints.telephoneNumber],
      decoration: InputDecoration(
        hintText: pais.ejemplo,
        prefixIcon: _SelectorPais(valor: pais, alCambiar: alCambiarPais),
        prefixIconConstraints: const BoxConstraints(minWidth: 108),
      ),
      validator: (valor) => UtilesTelefono.esMovilValido(valor ?? '', pais)
          ? null
          : pais.mensajeFormatoInvalido,
    );
  }
}

/// Quien crea su cuenta escribe el codigo que le llego al celular.
class _PasoVerificacion extends StatelessWidget {
  const _PasoVerificacion({
    required this.controladorCodigo,
    required this.alVolver,
  });

  final TextEditingController controladorCodigo;
  final VoidCallback alVolver;

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final desafio = controlador.desafio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: alVolver,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Volver',
              color: ColoresOnix.textoSuave,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirma tu número',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: ColoresOnix.textoSuave),
            children: [
              const TextSpan(
                text: 'Te enviamos un código de 6 dígitos por SMS al ',
              ),
              TextSpan(
                text: desafio == null
                    ? ''
                    : UtilesTelefono.formatoLegible(desafio.telefonoE164),
                style: const TextStyle(
                  color: ColoresOnix.texto,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '. Al confirmarlo se crea tu cuenta.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        CampoCodigoVerificacion(
          controlador: controladorCodigo,
          habilitado: !controlador.procesando,
          alCompletar: controlador.confirmarCodigo,
        ),

        if (desafio?.codigoDemo != null) ...[
          const SizedBox(height: 18),
          _AvisoDemostracion(codigo: desafio!.codigoDemo!),
        ],

        if (controlador.mensajeError != null) ...[
          const SizedBox(height: 18),
          _MensajeError(texto: controlador.mensajeError!),
        ],

        const SizedBox(height: 22),
        BotonDorado(
          texto: 'Verificar y crear cuenta',
          icono: Icons.verified_rounded,
          expandido: true,
          cargando: controlador.procesando,
          alPresionar: () =>
              controlador.confirmarCodigo(controladorCodigo.text),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed:
                controlador.procesando ? null : controlador.reenviarCodigo,
            child: const Text('Reenviar código'),
          ),
        ),
      ],
    );
  }
}

/// La invitacion ya sumo: confirmacion y la invitacion a participar.
class _CanjeListo extends StatelessWidget {
  const _CanjeListo({required this.resultado, required this.alQuererInvitar});

  final ResultadoCanje? resultado;
  final VoidCallback alQuererInvitar;

  @override
  Widget build(BuildContext context) {
    final resultado = this.resultado;
    final quien = resultado?.nombreInvitador;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: ColoresOnix.verde.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: ColoresOnix.verde,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '¡Invitación validada!',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontSize: 25),
        ),
        const SizedBox(height: 10),
        Text(
          quien == null || quien.isEmpty
              ? 'Tu código ya sumó un ticket a quien te invitó.'
              : 'Tu código ya sumó un ticket a $quien.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: ColoresOnix.texto, fontWeight: FontWeight.w600),
        ),
        if (resultado != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ColoresOnix.fondo,
              borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
              border: Border.all(color: ColoresOnix.borde),
            ),
            child: Column(
              children: [
                _FilaDato(etiqueta: 'Código', valor: resultado.codigoVisible),
                const SizedBox(height: 8),
                _FilaDato(
                  etiqueta: 'Celular',
                  valor: UtilesTelefono.formatoLegible(resultado.telefonoE164),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tu número y este dispositivo quedaron asociados a este código: '
            'no pueden validar otra invitación.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ColoresOnix.textoSuave,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 22),
        BotonDorado(
          texto: 'Yo también quiero invitar',
          icono: Icons.group_add_rounded,
          expandido: true,
          alPresionar: alQuererInvitar,
        ),
      ],
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            color: ColoresOnix.textoSuave,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ColoresOnix.texto,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Deja elegir el pais del celular: cambia el prefijo, el formato y el
/// largo esperado del numero. Por defecto Chile, la campana original.
class _SelectorPais extends StatelessWidget {
  const _SelectorPais({required this.valor, required this.alCambiar});

  final PaisTelefono valor;
  final ValueChanged<PaisTelefono> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<PaisTelefono>(
              value: valor,
              isDense: true,
              onChanged: (nuevo) {
                if (nuevo != null) alCambiar(nuevo);
              },
              items: [
                for (final pais in PaisTelefono.values)
                  DropdownMenuItem(
                    value: pais,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(pais.bandera, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          pais.prefijoInternacional,
                          style: const TextStyle(
                            color: ColoresOnix.texto,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: ColoresOnix.borde),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        texto,
        style: const TextStyle(
          color: ColoresOnix.texto,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Banner que confirma que la persona llegó por el link de alguien.
class _AvisoInvitacion extends StatelessWidget {
  const _AvisoInvitacion({this.nombreInvitador, this.yaUsado = false});

  final String? nombreInvitador;
  final bool yaUsado;

  @override
  Widget build(BuildContext context) {
    final quien = (nombreInvitador ?? '').isEmpty
        ? 'Te invitaron'
        : '$nombreInvitador te invitó';
    final texto = yaUsado
        ? 'Este código ya se validó desde este celular. Cada persona puede '
            'aceptar una sola invitación.'
        : '$quien. Este código es solo para ti y quedó reservado para este '
            'celular: al validarlo, tu número también queda anclado a él.';

    return _Aviso(
      icono: yaUsado ? Icons.info_rounded : Icons.card_giftcard_rounded,
      color: yaUsado ? ColoresOnix.ambar : ColoresOnix.verde,
      texto: texto,
    );
  }
}

/// Mientras el link genera el codigo de este dispositivo.
class _AvisoCargandoCodigo extends StatelessWidget {
  const _AvisoCargandoCodigo();

  @override
  Widget build(BuildContext context) {
    return const _Aviso(
      icono: Icons.hourglass_top_rounded,
      color: ColoresOnix.azulElectrico,
      texto: 'Preparando tu código exclusivo…',
      cargando: true,
    );
  }
}

/// El link no pudo entregar un codigo: se explica y se puede reintentar o
/// escribir un codigo a mano.
class _AvisoEnlaceFallido extends StatelessWidget {
  const _AvisoEnlaceFallido({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Aviso(
          icono: Icons.error_outline_rounded,
          color: ColoresOnix.rojo,
          texto: texto,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: alReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.color,
    required this.texto,
    this.cargando = false,
  });

  final IconData icono;
  final Color color;
  final String texto;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (cargando)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          else
            Icon(icono, size: 19, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: ColoresOnix.texto,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solo con el repositorio en memoria, que no envía SMS: el código se
/// muestra en pantalla para poder recorrer el registro sin backend.
class _AvisoDemostracion extends StatelessWidget {
  const _AvisoDemostracion({required this.codigo});

  final String codigo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresOnix.amarilloClaro,
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(
          color: ColoresOnix.amarilloOnix.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded,
              size: 19, color: ColoresOnix.azulOnix),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: ColoresOnix.azulOnix,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  const TextSpan(text: 'Modo demostración · tu código es '),
                  TextSpan(
                    text: codigo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeError extends StatelessWidget {
  const _MensajeError({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresOnix.rojo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(color: ColoresOnix.rojo.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 19, color: ColoresOnix.rojo),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: ColoresOnix.rojo,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CasillaBases extends StatelessWidget {
  const _CasillaBases({
    required this.valor,
    required this.texto,
    required this.alCambiar,
  });

  final bool valor;
  final String texto;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => alCambiar(!valor),
      borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: valor,
                onChanged: (nuevo) => alCambiar(nuevo ?? false),
                activeColor: ColoresOnix.azulOnix,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  color: ColoresOnix.textoSuave,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
