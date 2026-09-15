import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/utiles/codigo_referido.dart';

void main() {
  group('CodigoReferido', () {
    test('genera codigos validos y del largo esperado', () {
      for (var i = 0; i < 200; i++) {
        final codigo = CodigoReferido.generar();
        expect(codigo.length, CodigoReferido.largo);
        expect(CodigoReferido.esValido(codigo), isTrue);
      }
    });

    test('no usa caracteres ambiguos', () {
      for (var i = 0; i < 200; i++) {
        final codigo = CodigoReferido.generar();
        expect(codigo.contains(RegExp('[ILO01]')), isFalse);
      }
    });

    test('genera codigos distintos entre si', () {
      final generados = <String>{};
      for (var i = 0; i < 500; i++) {
        generados.add(CodigoReferido.generar());
      }
      // Con 31^7 combinaciones, 500 codigos no deberian colisionar.
      expect(generados.length, 500);
    });

    test('normaliza minusculas, guiones y el prefijo visible', () {
      final codigo = CodigoReferido.generar();
      final visible = CodigoReferido.paraMostrar(codigo);

      expect(CodigoReferido.normalizar(visible), codigo);
      expect(CodigoReferido.normalizar(visible.toLowerCase()), codigo);
      expect(CodigoReferido.normalizar('  $visible  '), codigo);
    });

    test('extrae el codigo desde un link de invitacion completo', () {
      final codigo = CodigoReferido.generar();
      final visible = CodigoReferido.paraMostrar(codigo);

      expect(
        CodigoReferido.normalizar('https://sorteo.onixdrive.cl/?ref=$visible'),
        codigo,
      );
      expect(
        CodigoReferido.normalizar('https://sorteo.onixdrive.cl/?r=$visible'),
        codigo,
      );
    });

    test('rechaza un codigo con un caracter cambiado', () {
      const alfabeto = CodigoReferido.alfabeto;
      final codigo = CodigoReferido.generar();

      // Cambiar un caracter del cuerpo rompe el digito verificador.
      final original = codigo[0];
      final reemplazo =
          alfabeto[(alfabeto.indexOf(original) + 1) % alfabeto.length];
      final alterado = reemplazo + codigo.substring(1);

      expect(CodigoReferido.esValido(alterado), isFalse);
    });

    test('rechaza largos incorrectos y caracteres fuera del alfabeto', () {
      expect(CodigoReferido.esValido(''), isFalse);
      expect(CodigoReferido.esValido('ABC'), isFalse);
      expect(CodigoReferido.esValido('AAAAAAAAAAAA'), isFalse);
      expect(CodigoReferido.esValido('AAAAAAA!'), isFalse);
    });
  });
}
