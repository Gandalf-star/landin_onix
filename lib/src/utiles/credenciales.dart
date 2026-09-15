import 'dart:convert';

/// Reglas del nombre de usuario y la contrasena de la cuenta.
///
/// Son las mismas que aplica la base de datos en
/// `cuenta_preparar_registro`; repetirlas aqui solo sirve para avisar
/// mientras la persona escribe, sin esperar la respuesta del servidor.
abstract final class UtilesCredenciales {
  static const largoMinimoUsuario = 3;
  static const largoMaximoUsuario = 20;
  static const largoMinimoContrasena = 8;

  /// bcrypt solo considera los primeros 72 bytes: mas largo seria engañoso.
  static const bytesMaximosContrasena = 72;

  static final _formatoUsuario = RegExp(r'^[a-z0-9][a-z0-9_.]{2,19}$');

  /// `  @Camila.Torres ` -> `camila.torres`.
  static String normalizarUsuario(String entrada) {
    var valor = entrada.trim().toLowerCase();
    while (valor.startsWith('@')) {
      valor = valor.substring(1);
    }
    return valor;
  }

  /// Mensaje de error del nombre de usuario, o `null` si es valido.
  static String? errorUsuario(String entrada) {
    final valor = normalizarUsuario(entrada);
    if (valor.length < largoMinimoUsuario) {
      return 'Usa al menos $largoMinimoUsuario caracteres';
    }
    if (valor.length > largoMaximoUsuario) {
      return 'Usa como máximo $largoMaximoUsuario caracteres';
    }
    if (!_formatoUsuario.hasMatch(valor)) {
      return 'Solo letras sin tilde, números, punto o guion bajo';
    }
    return null;
  }

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
