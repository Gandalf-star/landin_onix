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
      'Escribe tu nombre, elige una contraseña y confirma tu celular '
          'chileno o venezolano con el código que te llega por SMS. Un '
          'número = una persona.',
    ),
    (
      Icons.share_rounded,
      'Comparte tu link',
      'Pulsa «Compartir link por WhatsApp» y elige a todos los contactos que '
          'quieras. Cada persona que lo abre recibe su propio código.',
    ),
    (
      Icons.phonelink_lock_rounded,
      'Tu invitado valida su código',
      'Sin crear cuenta ni recibir SMS: escribe su celular y su número y su '
          'dispositivo quedan anclados al código. En ese momento sumas un '
          'ticket.',
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
}
