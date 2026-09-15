import 'dart:math';

/// Generacion y validacion de codigos de referido.
///
/// Formato: 8 caracteres (7 aleatorios + 1 digito verificador) tomados de un
/// alfabeto sin caracteres ambiguos, presentados como `ONX-XXXX-XXXX`.
///
/// El digito verificador permite rechazar codigos mal tipeados sin consultar
/// al servidor. NO es una medida de seguridad: la unicidad real la garantiza
/// la restriccion UNIQUE en base de datos.
abstract final class CodigoReferido {
  /// Sin I, L, O ni 0/1 para evitar confusiones al dictar el codigo.
  static const alfabeto = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const _largoCuerpo = 7;
  static const largo = _largoCuerpo + 1;
  static const prefijoVisible = 'ONX';

  static final _aleatorio = Random.secure();

  /// Genera un codigo nuevo. Quien lo llame debe verificar la unicidad contra
  /// la base de datos y reintentar ante colision.
  static String generar() {
    final cuerpo = List.generate(
      _largoCuerpo,
      (_) => alfabeto[_aleatorio.nextInt(alfabeto.length)],
    ).join();
    return '$cuerpo${_caracterVerificador(cuerpo)}';
  }

  /// Normaliza lo que el usuario pega: acepta `onx-7k4q-2p9m`, `ONX7K4Q2P9M`,
  /// un link completo o el codigo pelado.
  static String normalizar(String entrada) {
    var valor = entrada.trim();

    // Si pegaron un link, quedarse con el parametro `ref` o el ultimo tramo.
    final uri = Uri.tryParse(valor);
    if (uri != null && (uri.hasScheme || valor.contains('/'))) {
      final desdeQuery = uri.queryParameters['ref'] ?? uri.queryParameters['r'];
      if (desdeQuery != null && desdeQuery.isNotEmpty) {
        valor = desdeQuery;
      } else if (uri.pathSegments.isNotEmpty) {
        valor = uri.pathSegments.last;
      }
    }

    valor = valor.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (valor.length > largo && valor.startsWith(prefijoVisible)) {
      valor = valor.substring(prefijoVisible.length);
    }
    return valor;
  }

  /// Valida largo, alfabeto y digito verificador.
  static bool esValido(String normalizado) {
    if (normalizado.length != largo) return false;
    for (final caracter in normalizado.split('')) {
      if (!alfabeto.contains(caracter)) return false;
    }
    final cuerpo = normalizado.substring(0, _largoCuerpo);
    return normalizado[_largoCuerpo] == _caracterVerificador(cuerpo);
  }

  /// `7K4Q2P9M` -> `ONX-7K4Q-2P9M`.
  static String paraMostrar(String normalizado) {
    if (normalizado.length != largo) return normalizado;
    return '$prefijoVisible-${normalizado.substring(0, 4)}-'
        '${normalizado.substring(4)}';
  }

  /// Suma ponderada modulo el tamano del alfabeto.
  static String _caracterVerificador(String cuerpo) {
    var suma = 0;
    for (var i = 0; i < cuerpo.length; i++) {
      suma += (alfabeto.indexOf(cuerpo[i]) + 1) * (i + 2);
    }
    return alfabeto[suma % alfabeto.length];
  }
}
