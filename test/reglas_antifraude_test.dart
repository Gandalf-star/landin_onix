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

/// Crea la cuenta de alguien que va a invitar: pide el codigo y lo confirma
/// desde el dispositivo actual del repositorio (o desde [dispositivo]).
Future<Participante> registrar(
  RepositorioEnMemoria repositorio, {
  required String nombre,
  required String telefono,
  String contrasena = contrasenaPrueba,
  PaisTelefono pais = PaisTelefono.chile,
  String? dispositivo,
}) async {
  final anterior = repositorio.huellaDispositivo;
  repositorio.huellaDispositivo = dispositivo ?? anterior;
  try {
    final desafio = await repositorio.iniciarRegistro(
      nombre: nombre,
      contrasena: contrasena,
      telefono: telefono,
      pais: pais,
    );
    return await repositorio.confirmarVerificacion(
      idDesafio: desafio.id,
      codigo: desafio.codigoDemo!,
    );
  } finally {
    repositorio.huellaDispositivo = anterior;
  }
}

/// Valida un codigo de invitacion SIN cuenta ni SMS.
///
/// Como en la vida real, la persona invitada lo hace desde su propio
/// celular: si no se indica [dispositivo] se usa uno derivado de su
/// telefono. Al terminar se vuelve al dispositivo que habia.
Future<ResultadoCanje> canjear(
  RepositorioEnMemoria repositorio, {
  required String codigo,
  required String telefono,
  PaisTelefono pais = PaisTelefono.chile,
  String? dispositivo,
}) async {
  final digitos = telefono.replaceAll(RegExp(r'\D'), '');
  final anterior = repositorio.huellaDispositivo;
  repositorio.huellaDispositivo = dispositivo ?? 'celular_$digitos';
  try {
    return await repositorio.validarCodigo(
      codigoInvitacion: codigo,
      telefono: telefono,
      pais: pais,
    );
  } finally {
    repositorio.huellaDispositivo = anterior;
  }
}

/// Abre un link de invitacion desde [dispositivo] y devuelve el codigo que
/// le toco a ese dispositivo.
Future<CodigoAsignado> abrirLink(
  RepositorioEnMemoria repositorio,
  String token, {
  required String dispositivo,
}) async {
  final anterior = repositorio.huellaDispositivo;
  repositorio.huellaDispositivo = dispositivo;
  try {
    return await repositorio.obtenerCodigoDeEnlace(token);
  } finally {
    repositorio.huellaDispositivo = anterior;
  }
}

/// Un codigo individual nuevo de [idParticipante].
Future<InvitacionEmitida> generarUna(
  RepositorioEnMemoria repositorio,
  String idParticipante,
) =>
    repositorio.generarInvitacion(idParticipante);

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
  late Participante invitador;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repositorio = RepositorioEnMemoria();
    repositorio.huellaDispositivo = 'celular_de_camila';
    invitador = await registrar(
      repositorio,
      nombre: 'Camila Torres',
      telefono: '9 6483 1207',
    );
  });

  Future<int> ticketsDe(Participante quien) async =>
      (await repositorio.refrescarParticipante(quien.id)).tickets;

  group('Cuenta de quien invita', () {
    test('un registro completo queda verificado y sin tickets', () async {
      expect(invitador.telefonoE164, '+56964831207');
      expect(invitador.telefonoVerificado, isTrue);
      expect(invitador.codigoInvitador, isNull);
      expect(invitador.referidosValidos, 0);
    });

    test('el mismo numero no puede crear dos cuentas', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Otra Vez',
          contrasena: contrasenaPrueba,
          telefono: '+56 9 6483 1207',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.telefonoYaRegistrado);
    });

    test('generar una invitacion entrega un codigo unico y valido', () async {
      final invitacion = await generarUna(repositorio, invitador.id);

      expect(CodigoReferido.esValido(invitacion.codigo), isTrue);
      expect(invitacion.estado, EstadoInvitacion.pendiente);
      expect(invitacion.usadaEn, isNull);
    });
  });

  group('Link de invitación para muchos contactos', () {
    test('cada dispositivo que abre el link recibe un código distinto',
        () async {
      final enlace = await repositorio.miEnlace(invitador.id);

      final matias =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_matias');
      final javiera =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_javiera');
      final luis =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_luis');

      expect({matias.codigo, javiera.codigo, luis.codigo}, hasLength(3));
      expect(CodigoReferido.esValido(matias.codigo), isTrue);
      expect(matias.nombreInvitador, 'Camila');
      expect(matias.usado, isFalse);
      expect(await repositorio.misInvitaciones(invitador.id), hasLength(3));
    });

    test('el mismo dispositivo recibe siempre el mismo código', () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      final primero =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_matias');
      final segundo =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_matias');

      expect(segundo.codigo, primero.codigo);
      expect(await repositorio.misInvitaciones(invitador.id), hasLength(1));
    });

    test('cada contacto valida su código y cada uno suma un ticket', () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      final contactos = {
        'cel_matias': '9 6483 1208',
        'cel_javiera': '9 6483 1209',
        'cel_luis': '9 6483 1210',
      };
      for (final MapEntry(key: celular, value: numero) in contactos.entries) {
        final codigo =
            await abrirLink(repositorio, enlace.token, dispositivo: celular);
        await canjear(
          repositorio,
          codigo: codigo.codigoVisible,
          telefono: numero,
          dispositivo: celular,
        );
      }

      expect(await ticketsDe(invitador), 3);
      final alVolver =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_matias');
      expect(alVolver.usado, isTrue);
      final enlaceDespues = await repositorio.miEnlace(invitador.id);
      expect(enlaceDespues.token, enlace.token);
      expect(enlaceDespues.codigosEntregados, 3);
    });

    test('un código del link no se valida desde otro dispositivo', () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      final codigo =
          await abrirLink(repositorio, enlace.token, dispositivo: 'cel_matias');

      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: codigo.codigoVisible,
          telefono: '9 6483 1299',
          dispositivo: 'granja_de_cuentas',
        ),
      );
      expect(motivo, MotivoError.dispositivoNoIdentificado);
      expect(await ticketsDe(invitador), 0);
    });

    test('quien invita no puede abrir su propio link para sacar códigos',
        () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      final motivo = await motivoDelError(
        () => abrirLink(
          repositorio,
          enlace.token,
          dispositivo: 'celular_de_camila',
        ),
      );
      expect(motivo, MotivoError.dispositivoDelInvitador);
    });

    test('un link que no existe se rechaza', () async {
      final motivo = await motivoDelError(
        () => abrirLink(
          repositorio,
          CodigoReferido.generarToken(),
          dispositivo: 'cel_x',
        ),
      );
      expect(motivo, MotivoError.codigoInexistente);
    });

    test('un link entrega como máximo 50 códigos', () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      for (var i = 0; i < 50; i++) {
        await abrirLink(repositorio, enlace.token, dispositivo: 'cel_$i');
      }
      final motivo = await motivoDelError(
        () => abrirLink(repositorio, enlace.token, dispositivo: 'cel_51'),
      );
      expect(motivo, MotivoError.demasiadosIntentos);

      // Lleno, quien invita recibe un link nuevo.
      final nuevo = await repositorio.miEnlace(invitador.id);
      expect(nuevo.token, isNot(enlace.token));
      expect(nuevo.codigosEntregados, 0);
    });
  });

  group('Canje sin cuenta ni SMS', () {
    test('validar el código suma un ticket sin crear una cuenta', () async {
      final invitacion = await generarUna(repositorio, invitador.id);

      final resultado = await canjear(
        repositorio,
        codigo: invitacion.codigoVisible,
        telefono: '9 6483 1208',
      );

      expect(resultado.codigo, invitacion.codigo);
      expect(resultado.telefonoE164, '+56964831208');
      expect(resultado.nombreInvitador, 'Camila');
      expect(await ticketsDe(invitador), ConfigCampana.ticketsPorReferido);

      // El invitado no tiene cuenta: su número no sirve para entrar.
      final motivoIngreso = await motivoDelError(
        () => repositorio.iniciarSesion(
          telefono: '9 6483 1208',
          pais: PaisTelefono.chile,
          contrasena: contrasenaPrueba,
        ),
      );
      expect(motivoIngreso, MotivoError.credencialesIncorrectas);

      final usada = (await repositorio.misInvitaciones(invitador.id)).single;
      expect(usada.estado, EstadoInvitacion.usada);
      expect(usada.telefonoInvitado, UtilesTelefono.enmascarar('+56964831208'));
    });

    test('el código se acepta escrito de cualquier forma o como link',
        () async {
      final primera = await generarUna(repositorio, invitador.id);
      final segunda = await generarUna(repositorio, invitador.id);

      await canjear(
        repositorio,
        codigo: primera.codigoVisible.toLowerCase().replaceAll('-', ' '),
        telefono: '9 6483 1208',
      );
      await canjear(
        repositorio,
        codigo: 'https://sorteo.onixdrive.cl/?ref=${segunda.codigoVisible}',
        telefono: '9 6483 1209',
      );
      expect(await ticketsDe(invitador), 2);
    });

    test('un chileno puede invitar a un venezolano', () async {
      final invitacion = await generarUna(repositorio, invitador.id);

      final resultado = await canjear(
        repositorio,
        codigo: invitacion.codigoVisible,
        telefono: '414 987 6543',
        pais: PaisTelefono.venezuela,
      );

      expect(resultado.telefonoE164, '+584149876543');
      expect(await ticketsDe(invitador), 1);
    });
  });

  group('Un código sirve una sola vez', () {
    test('nadie puede reutilizar un código ya validado', () async {
      final invitacion = await generarUna(repositorio, invitador.id);
      await canjear(
        repositorio,
        codigo: invitacion.codigoVisible,
        telefono: '9 6483 1208',
      );

      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: invitacion.codigoVisible,
          telefono: '9 6483 1209',
        ),
      );
      expect(motivo, MotivoError.codigoYaUsado);
      expect(await ticketsDe(invitador), 1);
    });

    test('rechaza un código que no existe', () async {
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: CodigoReferido.generar(),
          telefono: '9 6483 1208',
        ),
      );
      expect(motivo, MotivoError.codigoInexistente);
    });

    test('rechaza un código mal escrito antes de consultar', () async {
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: 'ONX-1234-5678',
          telefono: '9 6483 1208',
        ),
      );
      expect(motivo, MotivoError.codigoMalFormado);
    });

    test('frena a quien prueba códigos al azar desde un dispositivo',
        () async {
      for (var i = 0; i < 8; i++) {
        await motivoDelError(
          () => canjear(
            repositorio,
            codigo: CodigoReferido.generar(),
            telefono: '9 6483 1208',
            dispositivo: 'celular_adivinador',
          ),
        );
      }

      // Aunque ahora traiga un código real, ese dispositivo está frenado.
      final invitacion = await generarUna(repositorio, invitador.id);
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: invitacion.codigoVisible,
          telefono: '9 6483 1208',
          dispositivo: 'celular_adivinador',
        ),
      );
      expect(motivo, MotivoError.demasiadosIntentos);
    });

    test('nadie puede validar su propio código', () async {
      final invitacion = await generarUna(repositorio, invitador.id);
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: invitacion.codigoVisible,
          telefono: '9 6483 1207',
          dispositivo: 'otro_celular_de_camila',
        ),
      );
      expect(motivo, MotivoError.autoReferido);
    });
  });

  group('Anclaje del teléfono', () {
    test('un número que ya validó una invitación no valida otra', () async {
      final primera = await generarUna(repositorio, invitador.id);
      await canjear(
        repositorio,
        codigo: primera.codigoVisible,
        telefono: '9 6483 1208',
      );

      // El mismo número, desde otro celular y con un código de otra persona.
      final otro = await registrar(
        repositorio,
        nombre: 'Javiera Soto',
        telefono: '9 6483 1209',
        dispositivo: 'celular_de_javiera',
      );
      final ajena = await generarUna(repositorio, otro.id);
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: ajena.codigoVisible,
          telefono: '9 6483 1208',
          dispositivo: 'celular_nuevo_de_matias',
        ),
      );
      expect(motivo, MotivoError.yaTieneInvitador);
      expect(await ticketsDe(otro), 0);
    });

    test('dos códigos del mismo link no suman con el mismo número', () async {
      final enlace = await repositorio.miEnlace(invitador.id);
      final a = await abrirLink(repositorio, enlace.token, dispositivo: 'cel_a');
      final b = await abrirLink(repositorio, enlace.token, dispositivo: 'cel_b');

      await canjear(
        repositorio,
        codigo: a.codigo,
        telefono: '9 6483 1208',
        dispositivo: 'cel_a',
      );
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: b.codigo,
          telefono: '9 6483 1208',
          dispositivo: 'cel_b',
        ),
      );
      expect(motivo, MotivoError.yaTieneInvitador);
      expect(await ticketsDe(invitador), 1);
    });
  });

  group('Anclaje del dispositivo', () {
    test(
      'un dispositivo que ya aceptó una invitación no acepta otra',
      () async {
        final primera = await generarUna(repositorio, invitador.id);
        final segunda = await generarUna(repositorio, invitador.id);

        await canjear(
          repositorio,
          codigo: primera.codigoVisible,
          telefono: '9 6483 1208',
          dispositivo: 'celular_de_matias',
        );

        // Otra persona intenta validar desde el mismo celular.
        final motivo = await motivoDelError(
          () => canjear(
            repositorio,
            codigo: segunda.codigoVisible,
            telefono: '9 6483 1209',
            dispositivo: 'celular_de_matias',
          ),
        );
        expect(motivo, MotivoError.dispositivoYaAnclado);
        expect(await ticketsDe(invitador), 1);
      },
    );

    test(
      'nadie puede validar códigos desde el dispositivo de quien invita',
      () async {
        final invitacion = await generarUna(repositorio, invitador.id);

        final motivo = await motivoDelError(
          () => canjear(
            repositorio,
            codigo: invitacion.codigoVisible,
            telefono: '9 6483 1299',
            dispositivo: 'celular_de_camila',
          ),
        );
        expect(motivo, MotivoError.dispositivoDelInvitador);
      },
    );

    test(
      'tampoco desde un dispositivo donde el invitador inició sesión',
      () async {
        final invitacion = await generarUna(repositorio, invitador.id);

        repositorio.huellaDispositivo = 'celular_prestado';
        await repositorio.iniciarSesion(
          telefono: '9 6483 1207',
          pais: PaisTelefono.chile,
          contrasena: contrasenaPrueba,
        );

        final motivo = await motivoDelError(
          () => canjear(
            repositorio,
            codigo: invitacion.codigoVisible,
            telefono: '9 6483 1208',
            dispositivo: 'celular_prestado',
          ),
        );
        expect(motivo, MotivoError.dispositivoDelInvitador);
      },
    );
  });

  group('Sin cadenas circulares', () {
    test('no puedes validar el código de alguien a quien invitaste',
        () async {
      // Camila invita a Matías; Matías crea su cuenta para invitar.
      final paraMatias = await generarUna(repositorio, invitador.id);
      await canjear(
        repositorio,
        codigo: paraMatias.codigoVisible,
        telefono: '9 6483 1208',
      );
      final matias = await registrar(
        repositorio,
        nombre: 'Matías Rivas',
        telefono: '9 6483 1208',
        dispositivo: 'celular_9 6483 1208',
      );

      // Camila no puede devolverle el favor validando un código de Matías.
      final deMatias = await generarUna(repositorio, matias.id);
      final motivo = await motivoDelError(
        () => canjear(
          repositorio,
          codigo: deMatias.codigoVisible,
          telefono: '9 6483 1207',
          dispositivo: 'celular_nuevo_de_camila',
        ),
      );
      expect(motivo, MotivoError.referidoCircular);
      expect(await ticketsDe(matias), 0);
    });
  });

  group('Verificación del teléfono al crear la cuenta', () {
    test('un codigo equivocado no crea al participante', () async {
      final desafio = await repositorio.iniciarRegistro(
        nombre: 'Matías Rivas',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1208',
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
          telefono: '9 6483 1208',
          pais: PaisTelefono.chile,
          contrasena: contrasenaPrueba,
        ),
      );
      expect(motivoIngreso, MotivoError.credencialesIncorrectas);
    });

    test('bloquea tras demasiados intentos fallidos', () async {
      final desafio = await repositorio.iniciarRegistro(
        nombre: 'Matías Rivas',
        contrasena: contrasenaPrueba,
        telefono: '9 6483 1208',
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
          nombre: 'Matías Rivas',
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
          nombre: 'Matías Rivas',
          contrasena: contrasenaPrueba,
          telefono: '999999999',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.numeroSospechoso);
    });

    test('el canje tambien rechaza numeros invalidos o falsos', () async {
      final invitacion = await generarUna(repositorio, invitador.id);
      expect(
        await motivoDelError(
          () => canjear(
            repositorio,
            codigo: invitacion.codigoVisible,
            telefono: '2 2345 6789',
          ),
        ),
        MotivoError.telefonoInvalido,
      );
      expect(
        await motivoDelError(
          () => canjear(
            repositorio,
            codigo: invitacion.codigoVisible,
            telefono: '999999999',
          ),
        ),
        MotivoError.numeroSospechoso,
      );
    });
  });

  group('Números venezolanos', () {
    test('acepta una cuenta con un móvil venezolano', () async {
      final participante = await registrar(
        repositorio,
        nombre: 'Luis Pérez',
        telefono: '412 903 4567',
        pais: PaisTelefono.venezuela,
        dispositivo: 'celular_de_luis',
      );

      expect(participante.telefonoE164, '+584129034567');
      expect(participante.telefonoVerificado, isTrue);
    });

    test('rechaza un móvil venezolano con prefijo inválido', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Luis Pérez',
          contrasena: contrasenaPrueba,
          telefono: '212 123 4567',
          pais: PaisTelefono.venezuela,
        ),
      );
      expect(motivo, MotivoError.telefonoInvalido);
    });

    test('rechaza un móvil venezolano con largo incorrecto', () async {
      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Luis Pérez',
          contrasena: contrasenaPrueba,
          telefono: '412 123 456',
          pais: PaisTelefono.venezuela,
        ),
      );
      expect(motivo, MotivoError.telefonoInvalido);
    });
  });

  group('Límite por dispositivo', () {
    test('corta las granjas de cuentas desde un mismo navegador', () async {
      repositorio.huellaDispositivo = 'granja';
      for (var i = 0; i < ConfigCampana.maxRegistrosPorDispositivo; i++) {
        await registrar(
          repositorio,
          nombre: 'Persona $i',
          telefono: '9 6483 130$i',
        );
      }

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Una más',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1399',
          pais: PaisTelefono.chile,
        ),
      );

      expect(motivo, MotivoError.limiteDispositivo);
    });
  });


  group('Premio de las tres cajas', () {
    Future<Participante> ganador({
      int tickets = ConfigCampana.metaTickets,
    }) async {
      await repositorio.simularInvitados(invitador.id, tickets);
      return repositorio.refrescarParticipante(invitador.id);
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

  group('Cuenta con celular y contraseña', () {
    test(
      'tras verificar el teléfono se entra con celular y contraseña',
      () async {
        final registrado = await registrar(
          repositorio,
          nombre: 'Camila Torres',
          telefono: '9 6483 1250',
          contrasena: 'MiClave2026',
        );

        await repositorio.cerrarSesion();
        expect(await repositorio.sesionActual(), isNull);

        // Da igual cómo se escriba el número: se normaliza a E.164.
        final ingresado = await repositorio.iniciarSesion(
          telefono: '+56 9 6483 1250',
          pais: PaisTelefono.chile,
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
        telefono: '9 6483 1250',
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarSesion(
          telefono: '9 6483 1250',
          pais: PaisTelefono.chile,
          contrasena: 'OtraClave99',
        ),
      );
      expect(motivo, MotivoError.credencialesIncorrectas);
    });

    test('bloquea el número tras varios intentos fallidos', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1250',
      );

      for (var i = 0; i < 5; i++) {
        await motivoDelError(
          () => repositorio.iniciarSesion(
            telefono: '9 6483 1250',
            pais: PaisTelefono.chile,
            contrasena: 'Adivinando$i',
          ),
        );
      }

      // Ni siquiera la contraseña correcta entra mientras dure el bloqueo.
      final motivo = await motivoDelError(
        () => repositorio.iniciarSesion(
          telefono: '9 6483 1250',
          pais: PaisTelefono.chile,
          contrasena: contrasenaPrueba,
        ),
      );
      expect(motivo, MotivoError.demasiadosIntentos);
    });

    test('el mismo número no se puede registrar dos veces', () async {
      await registrar(
        repositorio,
        nombre: 'Camila Torres',
        telefono: '9 6483 1250',
      );

      final motivo = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Rojas',
          contrasena: contrasenaPrueba,
          telefono: '9 6483 1250',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivo, MotivoError.telefonoYaRegistrado);
    });

    test('rechaza contraseñas débiles', () async {
      final motivoCorta = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          contrasena: 'solotexto',
          telefono: '9 6483 1250',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivoCorta, MotivoError.contrasenaInvalida);

      final motivoSinNumeros = await motivoDelError(
        () => repositorio.iniciarRegistro(
          nombre: 'Camila Torres',
          contrasena: 'Clave',
          telefono: '9 6483 1250',
          pais: PaisTelefono.chile,
        ),
      );
      expect(motivoSinNumeros, MotivoError.contrasenaInvalida);
    });
  });
}
