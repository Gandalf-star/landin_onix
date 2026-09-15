import 'package:flutter/services.dart';

/// Paises moviles que acepta la campana.
///
/// La campana nacio pensada solo para Chile; Venezuela se agrego despues
/// para poder probar el flujo completo con un numero real de ese pais. Cada
/// pais define su propio largo de numero nacional, sus prefijos de operadora
/// validos y como se agrupa al escribirlo.
enum PaisTelefono {
  chile,
  venezuela;

  String get codigoPais => switch (this) {
        PaisTelefono.chile => '56',
        PaisTelefono.venezuela => '58',
      };

  String get prefijoInternacional => '+$codigoPais';

  /// Bandera para mostrar en el selector del formulario.
  String get bandera => switch (this) {
        PaisTelefono.chile => '\u{1F1E8}\u{1F1F1}',
        PaisTelefono.venezuela => '\u{1F1FB}\u{1F1EA}',
      };

  String get nombre => switch (this) {
        PaisTelefono.chile => 'Chile',
        PaisTelefono.venezuela => 'Venezuela',
      };

  /// Cantidad de digitos del numero nacional (sin el codigo de pais).
  int get largoNacional => switch (this) {
        PaisTelefono.chile => 9,
        PaisTelefono.venezuela => 10,
      };

  /// Texto de ejemplo para el campo de telefono.
  String get ejemplo => switch (this) {
        PaisTelefono.chile => '9 1234 5678',
        PaisTelefono.venezuela => '412 123 4567',
      };

  /// Mensaje de error cuando el numero no tiene el formato movil esperado.
  String get mensajeFormatoInvalido => switch (this) {
        PaisTelefono.chile =>
          'Ingresa tu celular: 9 dígitos que empiezan con 9.',
        PaisTelefono.venezuela =>
          'Ingresa tu celular: 10 dígitos que empiezan con 412, 414, 416, '
              '424 o 426.',
      };
}

/// Utilidades de normalizacion telefonica para los paises de la campana.
///
/// El telefono normalizado en formato E.164 es la identidad unica de un
/// participante: sobre esa columna vive la restriccion UNIQUE que impide que
/// una misma persona se registre (y por lo tanto canjee un codigo) dos veces.
///
/// Todos los metodos que necesitan saber a que pais pertenece un numero que
/// todavia esta en formato nacional reciben [PaisTelefono] como parametro
/// opcional (por defecto Chile, para no romper el codigo existente). Los que
/// reciben un numero ya en E.164 (`enmascarar`, `formatoLegible`) deducen el
/// pais a partir del prefijo, porque ahi ya no hace falta que nadie lo diga.
abstract final class UtilesTelefono {
  /// Prefijos de operadoras moviles venezolanas.
  static const _prefijosMovilesVenezuela = [
    '412',
    '414',
    '416',
    '424',
    '426',
  ];

  /// Deja unicamente digitos.
  static String soloDigitos(String entrada) =>
      entrada.replaceAll(RegExp(r'[^0-9]'), '');

  /// Quita el codigo de pais y los ceros de marcacion nacional que la gente
  /// suele escribir: `+56 9...`, `0056 9...`, `09...` terminan todos en
  /// `9...` (o el equivalente venezolano empezando en `4...`).
  static String quitarPrefijos(
    String entrada, [
    PaisTelefono pais = PaisTelefono.chile,
  ]) {
    var digitos = soloDigitos(entrada);
    final codigoPais = pais.codigoPais;

    if (digitos.startsWith('00$codigoPais')) {
      digitos = digitos.substring(2 + codigoPais.length);
    } else if (digitos.length > pais.largoNacional &&
        digitos.startsWith(codigoPais)) {
      digitos = digitos.substring(codigoPais.length);
    }

    while (digitos.length > pais.largoNacional && digitos.startsWith('0')) {
      digitos = digitos.substring(1);
    }
    return digitos;
  }

  /// Valida que sea un movil del pais indicado.
  static bool esMovilValido(
    String entrada, [
    PaisTelefono pais = PaisTelefono.chile,
  ]) {
    final nacional = quitarPrefijos(entrada, pais);
    if (nacional.length != pais.largoNacional) return false;
    return switch (pais) {
      PaisTelefono.chile => nacional.startsWith('9'),
      PaisTelefono.venezuela =>
        _prefijosMovilesVenezuela.any(nacional.startsWith),
    };
  }

  /// Convierte a E.164 (`+569XXXXXXXX` o `+584XXXXXXXXX`) o devuelve `null`
  /// si no es un movil valido del pais indicado.
  static String? aE164(
    String entrada, [
    PaisTelefono pais = PaisTelefono.chile,
  ]) {
    if (!esMovilValido(entrada, pais)) return null;
    return '${pais.prefijoInternacional}${quitarPrefijos(entrada, pais)}';
  }

  /// Deduce el pais a partir de un telefono en E.164. Si no coincide con
  /// ninguno de los soportados (no deberia pasar con datos propios), asume
  /// Chile para no romper el formateo.
  static PaisTelefono paisDesde(String e164) {
    for (final pais in PaisTelefono.values) {
      if (e164.startsWith(pais.prefijoInternacional)) return pais;
    }
    return PaisTelefono.chile;
  }

  /// Enmascara un numero para mostrarlo en publico: `+56 9 •••• ••34`.
  static String enmascarar(String e164) {
    final digitos = soloDigitos(e164);
    if (digitos.length < 4) return '•••';
    final ultimos = digitos.substring(digitos.length - 2);
    return switch (paisDesde(e164)) {
      PaisTelefono.chile => '+56 9 •••• ••$ultimos',
      PaisTelefono.venezuela => '+58 4•• ••• ••$ultimos',
    };
  }

  /// Formato legible para el propio dueno del numero: `+56 9 1234 5678` o
  /// `+58 412 123 4567`.
  static String formatoLegible(String e164) {
    final pais = paisDesde(e164);
    final nacional = quitarPrefijos(e164, pais);
    if (nacional.length != pais.largoNacional) return e164;
    return switch (pais) {
      PaisTelefono.chile => '${pais.prefijoInternacional} '
          '${nacional.substring(0, 1)} ${nacional.substring(1, 5)} '
          '${nacional.substring(5)}',
      PaisTelefono.venezuela => '${pais.prefijoInternacional} '
          '${nacional.substring(0, 3)} ${nacional.substring(3, 6)} '
          '${nacional.substring(6)}',
    };
  }

  /// Formatea el numero nacional mientras se escribe, agrupado segun el
  /// pais: `9 1234 5678` en Chile, `412 123 4567` en Venezuela.
  static String formatoNacional(
    String nacional, [
    PaisTelefono pais = PaisTelefono.chile,
  ]) {
    final digitos = soloDigitos(nacional);
    if (digitos.isEmpty) return '';

    final grupos = switch (pais) {
      PaisTelefono.chile => const [1, 4, 4],
      PaisTelefono.venezuela => const [3, 3, 4],
    };

    final buffer = StringBuffer();
    var indice = 0;
    for (var i = 0; i < grupos.length && indice < digitos.length; i++) {
      if (i > 0) buffer.write(' ');
      final fin = (indice + grupos[i]).clamp(0, digitos.length);
      buffer.write(digitos.substring(indice, fin));
      indice = fin;
    }
    return buffer.toString();
  }

  /// Heuristica local para descartar entradas obviamente falsas antes de
  /// gastar un SMS. La deteccion real de VoIP se hace en el servidor.
  static bool pareceSospechoso(
    String entrada, [
    PaisTelefono pais = PaisTelefono.chile,
  ]) {
    final digitos = quitarPrefijos(entrada, pais);
    if (digitos.isEmpty) return true;

    return switch (pais) {
      // Todos los digitos iguales (999999999...) o secuencias triviales.
      PaisTelefono.chile => RegExp(r'^9(\d)\1{7}$').hasMatch(digitos) ||
          const ['912345678', '987654321'].contains(digitos),
      PaisTelefono.venezuela =>
        RegExp(r'^(?:412|414|416|424|426)(\d)\1{6}$').hasMatch(digitos) ||
            const ['4121234567', '4141234567'].contains(digitos),
    };
  }
}

/// Formatea la entrada del campo de telefono mientras se escribe, segun el
/// pais elegido, y limita el largo a lo que ese pais espera.
class FormateadorTelefono extends TextInputFormatter {
  const FormateadorTelefono({required this.pais});

  final PaisTelefono pais;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    var digitos = UtilesTelefono.soloDigitos(nuevo.text);
    if (digitos.length > pais.largoNacional) {
      digitos = digitos.substring(0, pais.largoNacional);
    }
    final texto = UtilesTelefono.formatoNacional(digitos, pais);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
