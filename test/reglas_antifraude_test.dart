import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/datos/modelos.dart';
import 'package:onix_referidos/src/datos/repositorio_memoria.dart';
import 'package:onix_referidos/src/datos/repositorio_referidos.dart';
import 'package:onix_referidos/src/nucleo/config_campana.dart';
import 'package:onix_referidos/src/utiles/codigo_referido.dart';
import 'package:onix_referidos/src/utiles/telefono.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrasena valida que usan las pruebas cuando no importa cual sea.
const contrasenaPrueba = 'Clave1234';

/// Registra a alguien de punta a punta: pide el codigo y lo confirma.
///
/// Si no se indica [nombreUsuario] se deriva del telefono, asi cada
/// registro de prueba tiene un usuario distinto sin tener que inventarlo.
///
/// Quien llega con un codigo de invitacion se registra, como en la vida
/// real, desde su propio celular: si no se indica [dispositivo] se usa uno
/// derivado de su telefono. Sin codigo se usa el dispositivo actual del
/// repositorio. Al terminar se vuelve al dispositivo que habia.
Future<Participante> registrar(
  RepositorioEnMemoria repositorio, {
  required String nombre,
  required String telefono,
  String? nombreUsuario,
  String contrasena = contrasenaPrueba,
  PaisTelefono pais = PaisTelefono.chile,
  String? invitador,
  String? dispositivo,
}) async {
  final digitos = telefono.replaceAll(RegExp(r'\D'), '');
  final anterior = repositorio.huellaDispositivo;
  repositorio.huellaDispositivo =
      dispositivo ?? (invitador != null ? 'celular_$digitos' : anterior);
  try {
    final desafio = await repositorio.iniciarRegistro(
      nombre: nombre,
      nombreUsuario: nombreUsuario ?? 'u$digitos',
      contrasena: contrasena,
      telefono: telefono,
      pais: pais,
      codigoInvitador: invitador,
    );
    return await repositorio.confirmarVerificacion(
      idDesafio: desafio.id,
      codigo: desafio.codigoDemo!,
    );
  } finally {
    repositorio.huellaDispositivo = anterior;
  }
}

/// Devuelve el motivo del error que lanza [operacion].
Future<MotivoError> motivoDelError(Future<void> Function() operacion) async {
  try {
    await operacion();
  } on ErrorReferidos catch (error) {
    return error.motivo;
  }
  fail('Se esperaba un ErrorReferidos y la operación no falló');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RepositorioEnMemoria repositorio;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repositorio = RepositorioEnMemoria();
  });

  group('Registro y codigo de invitacion', () {
    test(
      'un registro completo no trae invitador si no se usó código',
      () async {
        final participante = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
        );

        expect(participante.telefonoE164, '+56964831207');
        expect(participante.telefonoVerificado, isTrue);
        expect(participante.codigoInvitador, isNull);
        expect(participante.referidosValidos, 0);
      },
    );

    test('generar una invitacion entrega un codigo unico y valido', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );

      final invitacion = await repositorio.generarInvitacion(invitador.id);

      expect(CodigoReferido.esValido(invitacion.codigo), isTrue);
      expect(invitacion.estado, EstadoInvitacion.pendiente);
      expect(invitacion.usadaEn, isNull);
    });

    test(
      'el codigo de invitacion queda grabado en el registro y se cierra',
      () async {
        final invitador = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
        );
        final invitacion = await repositorio.generarInvitacion(invitador.id);

        final invitado = await registrar(
          repositorio,
          nombre: 'Matías Rivas',
          telefono: '9 6483 1208',
          invitador: invitacion.codigoVisible,
        );

        expect(invitado.codigoInvitador, invitacion.codigo);

        final actualizado = await repositorio.refrescarParticipante(
          invitador.id,
        );
        expect(actualizado.referidosValidos, 1);
        expect(actualizado.tickets, ConfigCampana.ticketsPorReferido);

        final invitaciones = await repositorio.misInvitaciones(invitador.id);
        final usada = invitaciones.firstWhere((i) => i.id == invitacion.id);
        expect(usada.estado, EstadoInvitacion.usada);
        expect(usada.nombreInvitado, 'Matías Rivas');
      },
    );

    test('el codigo de invitacion se acepta como link completo', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final invitacion = await repositorio.generarInvitacion(invitador.id);

      final invitado = await registrar(
        repositorio,
        nombre: 'Javiera Soto',
        telefono: '9 6483 1209',
        invitador:
            'https://sorteo.onixdrive.cl/?ref=${invitacion.codigoVisible}',
      );

      expect(invitado.codigoInvitador, invitacion.codigo);
    });

    test('cada invitacion generada es un codigo distinto', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );

      final primera = await repositorio.generarInvitacion(invitador.id);
      final segunda = await repositorio.generarInvitacion(invitador.id);

      expect(primera.codigo, isNot(segunda.codigo));

      final invitaciones = await repositorio.misInvitaciones(invitador.id);
      expect(invitaciones.length, 2);
    });
  });

  group('Números venezolanos', () {
    test('acepta un registro completo con un móvil venezolano', () async {
      final participante = await registrar(
        repositorio,
        nombre: 'Luis Pérez',
        telefono: '412 903 4567',
        pais: PaisTelefono.venezuela,
      );

      expect(participante.telefonoE164, '+584129034567');
      expect(participante.telefonoVerificado, isTrue);
    });

    test(
      'un chileno puede invitar a un venezolano y el código se cierra',
      () async {
        final invitador = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
        );
        final invitacion = await repositorio.generarInvitacion(invitador.id);

        final invitado = await registrar(
          repositorio,
          nombre: 'Luis Pérez',
          telefono: '414 987 6543',
          pais: PaisTelefono.venezuela,
          invitador: invitacion.codigoVisible,
        );

        expect(invitado.telefonoE164, '+584149876543');
        expect(invitado.codigoInvitador, invitacion.codigo);

        final actualizado = await repositorio.refrescarParticipante(
          invitador.id,
        );
        expect(actualizado.referidosValidos, 1);
      },
    );

    test(
      'rechaza un móvil venezolano con prefijo de operadora inválido',
      () async {
        final motivo = await motivoDelError(
          () => repositorio.iniciarRegistro(
            nombre: 'Luis Pérez',
            nombreUsuario: 'usuario_nuevo',
            contrasena: contrasenaPrueba,
            telefono: '212 123 4567',
            pais: PaisTelefono.venezuela,
          ),
        );
        expect(motivo, MotivoError.telefonoInvalido);
      },
    );

    test('rechaza un móvil venezolano con largo incorrecto', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Luis Pérez',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '412 123 456',
          pais: PaisTelefono.venezuela,
        ),
      );
      expect(motivo, MotivoError.telefonoInvalido);
    });

    test('un mismo número no se cuela registrándose por dos países', () async {
      // El mismo E.164 nunca puede coincidir entre países (prefijos +56 y
      // +58 distintos), pero un venezolano ya registrado no puede volver a
      // registrarse aunque cambie el país seleccionado en el formulario.
      await registrar(
        repositorio,
        nombre: 'Luis Pérez',
        telefono: '412 903 4567',
        pais: PaisTelefono.venezuela,
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Luis Otra Vez',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '412 903 4567',
          pais: PaisTelefono.venezuela,
        ),
      );
      expect(motivo, MotivoError.telefonoYaRegistrado);
    });
  });

  group('Un código de invitación sirve una sola vez', () {
    test('nadie puede reutilizar un código ya canjeado', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final invitacion = await repositorio.generarInvitacion(invitador.id);
      await registrar(
        repositorio,
        nombre: 'Matías Rivas',
        telefono: '9 6483 1208',
        invitador: invitacion.codigoVisible,
      );

      // Otra persona intenta usar el mismo código, ya canjeado.
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Javiera Soto',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1209',
          pais: PaisTelefono.chile,
          codigoInvitador: invitacion.codigoVisible,
        ),
      );
      expect(motivo, MotivoError.codigoYaUsado);
    });

    test('el mismo numero no puede registrarse dos veces', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Otra Vez',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '+56 9 6483 1207',
          pais: PaisTelefono.chile,
        ),
      );

      expect(motivo, MotivoError.telefonoYaRegistrado);
    });

    test('quien ya usó un código no puede volver a usar ninguno', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final invitacion = await repositorio.generarInvitacion(invitador.id);
      await registrar(
        repositorio,
        nombre: 'Matías Rivas',
        telefono: '9 6483 1208',
        invitador: invitacion.codigoVisible,
      );

      // El mismo invitado intenta reutilizar el mismo código.
      final motivoMismoCodigo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Matías Rivas',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1208',
          pais: PaisTelefono.chile,
          codigoInvitador: invitacion.codigoVisible,
        ),
      );
      expect(motivoMismoCodigo, MotivoError.yaTieneInvitador);

      // Y tampoco puede sumarse a otra persona con otro código.
      final otro = await registrar(
        repositorio,
        nombre: 'Javiera Soto',
        telefono: '9 6483 1209',
      );
      final otraInvitacion = await repositorio.generarInvitacion(otro.id);
      final motivoOtroCodigo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Matías Rivas',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1208',
          pais: PaisTelefono.chile,
          codigoInvitador: otraInvitacion.codigoVisible,
        ),
      );
      expect(motivoOtroCodigo, MotivoError.yaTieneInvitador);
    });

    test('el invitador no suma dos veces al mismo invitado', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final invitacion = await repositorio.generarInvitacion(invitador.id);
      await registrar(
        repositorio,
        nombre: 'Matías Rivas',
        telefono: '9 6483 1208',
        invitador: invitacion.codigoVisible,
      );

      try {
        await repositorio.iniciarRegistro(
          nombre: 'Matías Rivas',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1208',
          pais: PaisTelefono.chile,
          codigoInvitador: invitacion.codigoVisible,
        );
      } on ErrorReferidos catch (_) {
        // Esperado.
      }

      final actualizado = await repositorio.refrescarParticipante(invitador.id);
      expect(actualizado.referidosValidos, 1);
    });
  });

  group('Códigos inválidos y autorreferido', () {
    test('rechaza un codigo que no existe', () async {
      final codigoInexistente = CodigoReferido.generar();

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
          codigoInvitador: codigoInexistente,
        ),
      );

      expect(motivo, MotivoError.codigoInexistente);
    });

    test('rechaza un codigo mal escrito antes de consultar', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
          codigoInvitador: 'ONX-1234-5678',
        ),
      );

      expect(motivo, MotivoError.codigoMalFormado);
    });

    test('nadie puede usar su propio código para invitarse', () async {
      final participante = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final invitacion = await repositorio.generarInvitacion(participante.id);

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
          codigoInvitador: invitacion.codigoVisible,
        ),
      );

      // La identidad telefónica ya bloquea el intento antes de mirar el
      // código: un número registrado no puede volver a registrarse.
      expect(motivo, MotivoError.telefonoYaRegistrado);
    });
  });

  group('Verificación del teléfono', () {
    test('un codigo equivocado no crea al participante', () async {
      final desafio = await repositorio.iniciarRegistro(
        nombre: 'Camila Torres',
        nombreUsuario: 'usuario_nuevo',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1207',
        pais: PaisTelefono.chile,
      );

      final motivo = await motivoDelError(
        () => repositorio.confirmarVerificacion(
          idDesafio: desafio.id,
          codigo: '000000',
        ),
      );
      expect(motivo, MotivoError.codigoVerificacionIncorrecto);

      // La cuenta no llego a crearse: no se puede entrar con ella.
      final motivoIngreso = await motivoDelError(
        () => repositorio.iniciarSesion(
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
        ),
      );
      expect(motivoIngreso, MotivoError.credencialesIncorrectas);
    });

    test('bloquea tras demasiados intentos fallidos', () async {
      final desafio = await repositorio.iniciarRegistro(
        nombre: 'Camila Torres',
        nombreUsuario: 'usuario_nuevo',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1207',
        pais: PaisTelefono.chile,
      );

      for (var i = 0; i < 5; i++) {
        await motivoDelError(
          () => repositorio.confirmarVerificacion(
            idDesafio: desafio.id,
            codigo: '000000',
          ),
        );
      }

      final motivo = await motivoDelError(
        () => repositorio.confirmarVerificacion(
          idDesafio: desafio.id,
          codigo: desafio.codigoDemo!,
        ),
      );
      expect(motivo, MotivoError.demasiadosIntentos);
    });

    test('rechaza numeros que no son moviles chilenos', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '2 2345 6789',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.telefonoInvalido);
    });

    test('rechaza numeros obviamente falsos', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '999999999',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.numeroSospechoso);
    });
  });

  group('Límite por dispositivo', () {
    test('corta las granjas de cuentas desde un mismo navegador', () async {
      for (var i = 0; i < ConfigCampana.maxRegistrosPorDispositivo; i++) {
        await registrar(
          repositorio,
          nombre: 'Persona $i',
          telefono: '9 6483 120$i',
        );
      }

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Una más',
          nombreUsuario: 'usuario_nuevo',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1299',
          pais: PaisTelefono.chile,
        ),
      );

      expect(motivo, MotivoError.limiteDispositivo);
    });
  });

  group('Anclaje del dispositivo', () {
    test(
      'un dispositivo que ya aceptó una invitación no acepta otra',
      () async {
        final invitador = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
        );
        final primera = await repositorio.generarInvitacion(invitador.id);
        final segunda = await repositorio.generarInvitacion(invitador.id);

        await registrar(
          repositorio,
          nombre: 'Matías Rivas',
          telefono: '9 6483 1208',
          invitador: primera.codigoVisible,
          dispositivo: 'celular_de_matias',
        );

        // Otra persona intenta registrarse desde el mismo celular.
        repositorio.huellaDispositivo = 'celular_de_matias';
        final motivo = await motivoDelError(
          () => repositorio.iniciarRegistro(
            nombre: 'Javiera Soto',
            nombreUsuario: 'javiera',
            contrasena: contrasenaPrueba,
            telefono: '9 6483 1209',
            pais: PaisTelefono.chile,
            codigoInvitador: segunda.codigoVisible,
          ),
        );
        expect(motivo, MotivoError.dispositivoYaAnclado);

        final actualizado = await repositorio.refrescarParticipante(
          invitador.id,
        );
        expect(actualizado.tickets, 1);
      },
    );

    test(
      'nadie puede registrar invitados desde el dispositivo de quien invita',
      () async {
        final invitador = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
        );
        final invitacion = await repositorio.generarInvitacion(invitador.id);

        // Mismo navegador desde el que se registró Camila.
        final motivo = await motivoDelError(
          () => repositorio.iniciarRegistro(
            nombre: 'Número Inventado',
            nombreUsuario: 'inventado',
            contrasena: contrasenaPrueba,
            telefono: '9 6483 1299',
            pais: PaisTelefono.chile,
            codigoInvitador: invitacion.codigoVisible,
          ),
        );
        expect(motivo, MotivoError.dispositivoDelInvitador);
      },
    );

    test(
      'tampoco desde un dispositivo donde el invitador inició sesión',
      () async {
        final invitador = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
          nombreUsuario: 'camila',
        );
        final invitacion = await repositorio.generarInvitacion(invitador.id);

        repositorio.huellaDispositivo = 'celular_prestado';
        await repositorio.iniciarSesion(
          nombreUsuario: 'camila',
          contrasena: contrasenaPrueba,
        );

        final motivo = await motivoDelError(
          () => repositorio.iniciarRegistro(
            nombre: 'Matías Rivas',
            nombreUsuario: 'matias',
            contrasena: contrasenaPrueba,
            telefono: '9 6483 1208',
            pais: PaisTelefono.chile,
            codigoInvitador: invitacion.codigoVisible,
          ),
        );
        expect(motivo, MotivoError.dispositivoDelInvitador);
      },
    );

    test('el anclaje se vuelve a revisar al confirmar el SMS', () async {
      final invitador = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      final primera = await repositorio.generarInvitacion(invitador.id);
      final segunda = await repositorio.generarInvitacion(invitador.id);

      // Dos registros empiezan a la vez desde el mismo celular: ninguno
      // está anclado todavía, así que ambos pasan el primer paso.
      repositorio.huellaDispositivo = 'celular_compartido';
      final desafioUno = await repositorio.iniciarRegistro(
        nombre: 'Matías Rivas',
        nombreUsuario: 'matias',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1208',
        pais: PaisTelefono.chile,
        codigoInvitador: primera.codigoVisible,
      );
      final desafioDos = await repositorio.iniciarRegistro(
        nombre: 'Javiera Soto',
        nombreUsuario: 'javiera',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1209',
        pais: PaisTelefono.chile,
        codigoInvitador: segunda.codigoVisible,
      );

      await repositorio.confirmarVerificacion(
        idDesafio: desafioUno.id,
        codigo: desafioUno.codigoDemo!,
      );
      final motivo = await motivoDelError(
        () => repositorio.confirmarVerificacion(
          idDesafio: desafioDos.id,
          codigo: desafioDos.codigoDemo!,
        ),
      );
      expect(motivo, MotivoError.dispositivoYaAnclado);
    });
  });

  group('Premio de las tres cajas', () {
    Future<Participante> ganador({
      int tickets = ConfigCampana.metaTickets,
    }) async {
      final participante = await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
      );
      await repositorio.simularInvitados(participante.id, tickets);
      return repositorio.refrescarParticipante(participante.id);
    }

    test('sin 50 tickets no se puede reclamar', () async {
      final participante = await ganador(tickets: 49);
      expect(participante.puedeReclamar, isFalse);

      final motivo = await motivoDelError(
        () => repositorio.reclamarPremio(participante.id),
      );
      expect(motivo, MotivoError.premioNoDisponible);
    });

    test(
      'con 50 tickets las cajas quedan listas sin revelar los premios',
      () async {
        final participante = await ganador();
        expect(participante.puedeReclamar, isTrue);

        final reclamo = await repositorio.reclamarPremio(participante.id);

        expect(reclamo.estado, EstadoReclamo.cajasListas);
        expect(reclamo.cajaAbierta, isFalse);
        expect(reclamo.premio, isNull);
        expect(reclamo.codigoConfirmacion, isNull);
        // Nada que inspeccionar: el orden de las cajas no sale antes de abrir.
        expect(reclamo.distribucion, isEmpty);
      },
    );

    test(
      'abrir una caja entrega su premio y un código de confirmación',
      () async {
        final participante = await ganador();
        final reclamo = await repositorio.reclamarPremio(participante.id);

        final abierto = await repositorio.abrirCaja(
          idParticipante: participante.id,
          idReclamo: reclamo.id,
          caja: 1,
        );

        expect(abierto.cajaAbierta, isTrue);
        expect(abierto.cajaElegida, 1);
        expect(abierto.premio, abierto.distribucion[1]);
        expect(abierto.distribucion.toSet(), PremioCaja.values.toSet());
        expect(abierto.codigoConfirmacion, hasLength(10));
        expect(
          abierto.codigoConfirmacionVisible,
          matches(RegExp(r'^PRM-[2-9A-HJKMNP-Z]{5}-[2-9A-HJKMNP-Z]{5}$')),
        );
      },
    );

    test('una caja abierta no se puede cambiar por otra', () async {
      final participante = await ganador();
      final reclamo = await repositorio.reclamarPremio(participante.id);

      final primera = await repositorio.abrirCaja(
        idParticipante: participante.id,
        idReclamo: reclamo.id,
        caja: 0,
      );
      final otra = await repositorio.abrirCaja(
        idParticipante: participante.id,
        idReclamo: reclamo.id,
        caja: 2,
      );

      expect(otra.cajaElegida, 0);
      expect(otra.premio, primera.premio);
      expect(otra.codigoConfirmacion, primera.codigoConfirmacion);
    });

    test('reclamar otra vez devuelve el mismo reclamo, sin barajar', () async {
      final participante = await ganador();
      final uno = await repositorio.reclamarPremio(participante.id);
      final dos = await repositorio.reclamarPremio(participante.id);
      expect(dos.id, uno.id);
    });

    test(
      'los premios cambian de lugar entre un reclamo y el siguiente',
      () async {
        final participante = await ganador();
        final vistos = <String>{};
        List<PremioCaja>? anterior;

        for (var i = 0; i < 30; i++) {
          final reclamo = await repositorio.reclamarPremio(participante.id);
          final abierto = await repositorio.abrirCaja(
            idParticipante: participante.id,
            idReclamo: reclamo.id,
            caja: 0,
          );
          final orden = abierto.distribucion;
          if (anterior != null) {
            expect(
              orden,
              isNot(equals(anterior)),
              reason: 'nunca se repite el orden del reclamo anterior',
            );
          }
          vistos.add(orden.map((p) => p.name).join(','));
          anterior = orden;
          await repositorio.reiniciarPremio(participante.id);
        }

        // Seis órdenes posibles: con 30 reclamos al azar aparecen casi todos.
        expect(vistos.length, greaterThanOrEqualTo(4));
      },
    );
  });

  group('Cuenta con usuario y contraseña', () {
    test(
      'tras verificar el teléfono se entra con usuario y contraseña',
      () async {
        final registrado = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1207',
          nombreUsuario: '@Camila.Torres',
          contrasena: 'MiClave2026',
        );
        expect(registrado.nombreUsuario, 'camila.torres');

        await repositorio.cerrarSesion();
        expect(await repositorio.sesionActual(), isNull);

        final ingresado = await repositorio.iniciarSesion(
          nombreUsuario: 'CAMILA.TORRES',
          contrasena: 'MiClave2026',
        );
        expect(ingresado.id, registrado.id);
        expect((await repositorio.sesionActual())?.id, registrado.id);
      },
    );

    test('una contraseña equivocada no deja entrar', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
        nombreUsuario: 'camila',
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarSesion(
          nombreUsuario: 'camila',
          contrasena: 'OtraClave99',
        ),
      );
      expect(motivo, MotivoError.credencialesIncorrectas);
    });

    test('bloquea el usuario tras varios intentos fallidos', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
        nombreUsuario: 'camila',
      );

      for (var i = 0; i < 5; i++) {
        await motivoDelError(
          () => repositorio.iniciarSesion(
            nombreUsuario: 'camila',
            contrasena: 'Adivinando$i',
          ),
        );
      }

      // Ni siquiera la contraseña correcta entra mientras dure el bloqueo.
      final motivo = await motivoDelError(
        () => repositorio.iniciarSesion(
          nombreUsuario: 'camila',
          contrasena: contrasenaPrueba,
        ),
      );
      expect(motivo, MotivoError.demasiadosIntentos);
    });

    test('el nombre de usuario no se puede repetir', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1207',
        nombreUsuario: 'camila',
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Rojas',
          nombreUsuario: 'Camila',
          contrasena: contrasenaPrueba,
          telefono: '9 7777 1234',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.usuarioYaRegistrado);
    });

    test('rechaza contraseñas débiles y usuarios mal formados', () async {
      final motivoClave = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'camila',
          contrasena: 'solotexto',
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivoClave, MotivoError.contrasenaInvalida);

      final motivoUsuario = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          nombreUsuario: 'camila torres',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivoUsuario, MotivoError.usuarioInvalido);
    });
  });
}
