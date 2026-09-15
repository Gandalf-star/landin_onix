import 'package:flutter/material.dart';

/// Toda la configuracion comercial de la campana vive aqui, para que cambiar
/// metas o textos no obligue a tocar la interfaz.
///
/// Los montos van en pesos chilenos. Los telefonos aceptan moviles chilenos
/// y venezolanos (ver [PaisTelefono] en `utiles/telefono.dart`).
///
/// Los premios de las cajas estan en [PremioCaja] (`datos/modelos.dart`): el
/// servidor los conoce por su clave, asi que su lista no es configurable
/// solo desde aqui.
abstract final class ConfigCampana {
  static const nombreMarca = 'Onix Drive';
  static const nombreCampana = 'Reto 50 Onix';
  static const pais = 'Chile';

  /// Tickets necesarios para reclamar el premio. Debe coincidir con
  /// `fn_meta_tickets()` en la base de datos.
  static const metaTickets = 50;

  /// Dominio publico donde se sirve esta landing. Se usa para armar el link
  /// de invitacion cuando el navegador no expone un origen valido.
  static const origenPorDefecto = 'https://sorteo.onixdrive.cl';

  /// Horas que el servidor registra como ventana de maduracion de un
  /// referido valido, para poder revertir fraude detectado tarde.
  static const horasMaduracion = 72;

  /// Horas que un codigo de invitacion de un solo uso permanece disponible
  /// antes de vencer si nadie lo canjea. Pasado ese plazo hay que generar
  /// uno nuevo para volver a invitar a esa persona.
  static const horasExpiracionInvitacion = 168; // 7 dias

  /// Tickets que otorga cada invitado verificado con su dispositivo anclado.
  static const ticketsPorReferido = 1;

  /// Maximo de registros permitidos desde un mismo dispositivo en 24 horas.
  static const maxRegistrosPorDispositivo = 3;

  static const whatsappSoporte = '+56 9 0000 0000';
  static const urlPlayStore =
      'https://play.google.com/store/apps/details?id=com.onixdrive.mobile';
  static const urlAppStore =
      'https://apps.apple.com/cl/app/onix-drive/id000000000';

  /// Pasos que se muestran en la seccion "Cómo funciona".
  static const pasos = <(IconData, String, String)>[
    (
      Icons.phone_iphone_rounded,
      'Crea tu cuenta',
      'Elige tu usuario y contraseña, y confirma tu celular chileno o '
          'venezolano con el código que te llega por SMS. Un número = una '
          'persona.',
    ),
    (
      Icons.qr_code_2_rounded,
      'Genera un código por invitado',
      'Por cada persona que quieras invitar generas un código exclusivo y lo '
          'compartes por WhatsApp. Sirve una sola vez.',
    ),
    (
      Icons.phonelink_lock_rounded,
      'Tu invitado ancla su celular',
      'Se registra con ese código desde su propio celular, que queda anclado '
          'al código para siempre. En ese momento sumas un ticket.',
    ),
    (
      Icons.redeem_rounded,
      'Llega a 50 y abre tu caja',
      'Con 50 tickets reclamas tu premio: eliges una de tres cajas cerradas y '
          'te llevas lo que hay dentro.',
    ),
  ];

  /// Lo que pasa desde que se pulsa «Reclamar premio» hasta la entrega.
  static const pasosReclamo = <(String, String, String)>[
    (
      '01',
      'Pulsa «Reclamar premio»',
      'Aparece en tu panel al juntar $metaTickets tickets. En ese instante el '
          'sistema esconde los tres premios en tres cajas, en un orden al azar '
          'que cambia en cada reclamo.',
    ),
    (
      '02',
      'Elige una de las tres cajas',
      'Nadie sabe qué hay en cada una: el orden queda sellado en nuestro '
          'servidor y no llega a tu pantalla hasta que abres. Solo puedes '
          'abrir una.',
    ),
    (
      '03',
      'Recibe tu ticket ganador',
      'Tu premio aparece en un ticket con un código de confirmación único, y '
          'te mostramos qué había en las otras dos cajas.',
    ),
    (
      '04',
      'Validamos y entregamos',
      'El equipo Onix verifica el código y a tus invitados, y te contacta al '
          'número con el que te registraste para entregarte el premio.',
    ),
  ];

  static const preguntas = <(String, String)>[
    (
      '¿Cuánto cuesta participar?',
      'Nada. Participar es gratis: solo necesitas un número de teléfono '
          'chileno o venezolano real que puedas verificar.',
    ),
    (
      '¿Qué premios hay en las cajas?',
      'Tres: 1 viaje gratis, un regalo Onix y \$3.000 de saldo Onix. Cada caja '
          'esconde un premio distinto y te llevas el de la caja que abras.',
    ),
    (
      '¿Cuándo suma un ticket un invitado?',
      'Cuando esa persona se registra con el código que generaste para ella, '
          'confirma su celular por SMS y lo hace desde su propio dispositivo, '
          'que queda anclado a ese código. Los registros sin verificar no '
          'suman.',
    ),
    (
      '¿Por qué mi invitado tiene que usar su propio celular?',
      'Porque cada dispositivo se ancla a un único código en toda la '
          'campaña. Un celular que ya aceptó una invitación no puede aceptar '
          'otra, y un código no se puede canjear desde el dispositivo de quien '
          'lo generó. Así nadie suma invitados falsos desde un mismo teléfono.',
    ),
    (
      '¿Se puede saber en qué caja está cada premio?',
      'No. El orden se decide al azar en nuestro servidor en el momento en '
          'que reclamas, cambia en cada reclamo y no llega a tu navegador '
          'hasta que eliges. Una vez abierta la caja, la elección es '
          'definitiva.',
    ),
    (
      '¿Cómo recibo mi premio?',
      'Tu ticket ganador trae un código de confirmación. El equipo de Onix '
          'Drive lo verifica junto con tus invitados y te contacta al número '
          'con el que te registraste para coordinar la entrega.',
    ),
    (
      '¿Cómo vuelvo a entrar a mi cuenta?',
      'Con el nombre de usuario y la contraseña que elegiste al registrarte. '
          'El código por SMS se pide una sola vez, para confirmar que el '
          'celular es tuyo al crear la cuenta.',
    ),
    (
      '¿Qué pasa si alguien intenta hacer trampa?',
      'Detectamos números virtuales, registros repetidos, dispositivos que '
          'intentan aceptar más de una invitación y cadenas circulares. Antes '
          'de entregar un premio revisamos cada invitado: los tickets '
          'conseguidos con trampa se anulan y la cuenta queda fuera.',
    ),
    (
      '¿Qué es Onix Drive?',
      'Es nuestra plataforma de movilidad: pides tu viaje, pones tu precio y '
          'te mueves con conductores verificados. Esta campaña existe para '
          'que más gente la conozca.',
    ),
  ];

  /// Reglas anti-trampa que se muestran publicamente: generan confianza y
  /// desalientan el fraude antes de que ocurra.
  static const reglasJuegoLimpio = <(IconData, String, String)>[
    (
      Icons.verified_user_rounded,
      'Un teléfono, una participación',
      'Cada cuenta se crea confirmando el celular con un código por SMS. Los '
          'números repetidos o virtuales no pasan.',
    ),
    (
      Icons.lock_clock_rounded,
      'Cada código sirve una sola vez',
      'El código de invitación se genera para una persona y se cierra en '
          'cuanto ella lo usa. Quien te invitó queda grabado para siempre.',
    ),
    (
      Icons.phonelink_lock_rounded,
      'Un dispositivo, una invitación',
      'El celular del invitado queda anclado al código que canjea. No puede '
          'aceptar otra invitación, ni se puede usar el dispositivo de quien '
          'invita.',
    ),
    (
      Icons.inventory_2_rounded,
      'Cajas selladas en el servidor',
      'El orden de los premios se sortea en el servidor en cada reclamo y no '
          'llega a tu pantalla hasta que abres tu caja. No hay forma de '
          'espiarlo.',
    ),
    (
      Icons.confirmation_number_rounded,
      'Código de confirmación único',
      'Cada ticket ganador lleva un código irrepetible. Sin un código válido '
          'no hay entrega, y cada código se entrega una sola vez.',
    ),
    (
      Icons.fact_check_rounded,
      'Revisión antes de entregar',
      'Antes de entregar revisamos los números, dispositivos y códigos de '
          'los invitados del ganador. Los tickets con trampa se anulan.',
    ),
  ];
}
