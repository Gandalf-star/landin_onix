import 'dart:convert';

/// Reglas de la contrasena de la cuenta.
///
/// Son las mismas que aplica la base de datos en
/// `cuenta_preparar_registro`; repetirlas aqui solo sirve para avisar
/// mientras la persona escribe, sin esperar la respuesta del servidor.
abstract final class UtilesCredenciales {
  static const largoMinimoContrasena = 8;

  /// bcrypt solo considera los primeros 72 bytes: mas largo seria engañoso.
  static const bytesMaximosContrasena = 72;

  /// Mensaje de error de la contrasena, o `null` si es valida.
  static String? errorContrasena(String contrasena) {
    if (contrasena.length < largoMinimoContrasena) {
      return 'Usa al menos $largoMinimoContrasena caracteres';
    }
    if (utf8.encode(contrasena).length > bytesMaximosContrasena) {
      return 'Es demasiado larga';
    }
    if (!RegExp('[A-Za-z]').hasMatch(contrasena) ||
        !RegExp('[0-9]').hasMatch(contrasena)) {
      return 'Combina letras y números';
    }
    return null;
  }
}
