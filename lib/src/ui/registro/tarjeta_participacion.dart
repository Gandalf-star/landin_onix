import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../datos/controlador_referidos.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../../utiles/codigo_referido.dart';
import '../../utiles/credenciales.dart';
import '../../utiles/telefono.dart';
import '../componentes/botones.dart';
import 'campo_codigo.dart';

/// Tarjeta blanca del hero con el flujo completo de participacion.
///
/// - Registro: datos de la cuenta -> codigo por SMS al celular -> panel.
/// - Ingreso: celular y contrasena -> panel, sin SMS.
class TarjetaParticipacion extends StatefulWidget {
  const TarjetaParticipacion({super.key});

  @override
  State<TarjetaParticipacion> createState() => _TarjetaParticipacionState();
}

class _TarjetaParticipacionState extends State<TarjetaParticipacion> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _contrasena = TextEditingController();
  final _telefono = TextEditingController();
  final _codigoInvitador = TextEditingController();
  final _codigoVerificacion = TextEditingController();

  bool _modoIngreso = false;
  bool _verContrasena = false;
  bool _aceptaBases = false;
  bool _codigoVieneDeLink = false;
  PaisTelefono _pais = PaisTelefono.chile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final detectado = ProveedorCampana.accion(context).codigoInvitadorDetectado;
      if (detectado != null && mounted) {
        setState(() {
          _codigoInvitador.text = CodigoReferido.paraMostrar(detectado);
          _codigoVieneDeLink = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _contrasena.dispose();
    _telefono.dispose();
    _codigoInvitador.dispose();
    _codigoVerificacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlador = ProveedorCampana.de(context);
    final enVerificacion = controlador.etapa == EtapaRegistro.verificacion;

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
        child: enVerificacion
            ? _PasoVerificacion(
                controladorCodigo: _codigoVerificacion,
                alVolver: () {
                  _codigoVerificacion.clear();
                  controlador.volverADatos();
                },
              )
            : _construirPasoDatos(context, controlador),
      ),
    );
  }

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
                  : 'Crea tu cuenta en menos de un minuto. Confirmaremos tu '
                      'celular con un código por SMS.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: ColoresOnix.textoSuave),
            ),
            const SizedBox(height: 24),

            if (_codigoVieneDeLink && !_modoIngreso) ...[
              const _AvisoInvitacion(),
              const SizedBox(height: 18),
            ],

            if (!_modoIngreso) ...[
              _Etiqueta('Tu nombre'),
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

            _Etiqueta('Tu celular'),
            TextFormField(
              key: ValueKey(_pais),
              controller: _telefono,
              keyboardType: TextInputType.phone,
              inputFormatters: [FormateadorTelefono(pais: _pais)],
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                hintText: _pais.ejemplo,
                prefixIcon: _SelectorPais(
                  valor: _pais,
                  alCambiar: (nuevo) => setState(() {
                    _pais = nuevo;
                    _telefono.clear();
                  }),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 108),
              ),
              validator: (valor) =>
                  UtilesTelefono.esMovilValido(valor ?? '', _pais)
                      ? null
                      : _pais.mensajeFormatoInvalido,
            ),
            const SizedBox(height: 16),

            _Etiqueta('Contraseña'),
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
              const SizedBox(height: 16),
              _Etiqueta('Código de invitación (opcional)'),
              TextFormField(
                controller: _codigoInvitador,
                readOnly: _codigoVieneDeLink,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'ONX-XXXX-XXXX',
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
                  if (texto.isEmpty) return null;
                  return CodigoReferido.esValido(
                    CodigoReferido.normalizar(texto),
                  )
                      ? null
                      : 'Ese código no es válido';
                },
              ),
              const SizedBox(height: 18),
              _CasillaBases(
                valor: _aceptaBases,
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
                  controlador.limpiarError();
                  _formulario.currentState?.reset();
                  setState(() {
                    _modoIngreso = !_modoIngreso;
                    _contrasena.clear();
                  });
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
      codigoInvitador: _codigoInvitador.text,
    );
  }
}

/// Paso 2: la persona escribe el codigo que le llego al celular.
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
              const TextSpan(
                text: '. Al confirmarlo se crea tu cuenta.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        CampoCodigoVerificacion(
          controlador: controladorCodigo,
          habilitado: !controlador.procesando,
          alCompletar: (codigo) => controlador.confirmarCodigo(codigo),
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
            onPressed: controlador.procesando
                ? null
                : () => controlador.reenviarCodigo(),
            child: const Text('Reenviar código'),
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
  const _AvisoInvitacion();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresOnix.verde.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(MedidasOnix.radioChico),
        border: Border.all(color: ColoresOnix.verde.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.card_giftcard_rounded,
              size: 19, color: ColoresOnix.verde),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Llegaste con una invitación. Regístrate desde tu propio '
              'celular: este dispositivo quedará anclado a ese código.',
              style: TextStyle(
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
  const _CasillaBases({required this.valor, required this.alCambiar});

  final bool valor;
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
            const Expanded(
              child: Text(
                'Acepto las bases del ${ConfigCampana.nombreCampana} y que '
                'me envíen un SMS para verificar mi número.',
                style: TextStyle(
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
