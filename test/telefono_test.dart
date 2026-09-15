import 'package:flutter_test/flutter_test.dart';
import 'package:onix_referidos/src/utiles/telefono.dart';

void main() {
  group('UtilesTelefono (Chile)', () {
    test('acepta un movil chileno escrito de varias formas', () {
      const equivalentes = [
        '912345670',
        '9 1234 5670',
        '+56 9 1234 5670',
        '56912345670',
        '0056912345670',
        '(9) 1234-5670',
      ];

      for (final entrada in equivalentes) {
        expect(
          UtilesTelefono.aE164(entrada),
          '+56912345670',
          reason: 'Fallo con la entrada "$entrada"',
        );
      }
    });

    test('rechaza numeros que no son moviles chilenos', () {
      expect(UtilesTelefono.esMovilValido('212345678'), isFalse); // fijo
      expect(UtilesTelefono.esMovilValido('91234567'), isFalse); // corto
      expect(UtilesTelefono.esMovilValido('9123456789'), isFalse); // largo
      expect(UtilesTelefono.esMovilValido(''), isFalse);
      expect(UtilesTelefono.aE164('212345678'), isNull);
    });

    test('detecta numeros obviamente falsos', () {
      expect(UtilesTelefono.pareceSospechoso('999999999'), isTrue);
      expect(UtilesTelefono.pareceSospechoso('900000000'), isTrue);
      expect(UtilesTelefono.pareceSospechoso('912345678'), isTrue);
      expect(UtilesTelefono.pareceSospechoso('987654321'), isTrue);
      expect(UtilesTelefono.pareceSospechoso('964831207'), isFalse);
    });

    test('enmascara sin revelar el numero completo', () {
      final enmascarado = UtilesTelefono.enmascarar('+56964831207');
      expect(enmascarado.contains('07'), isTrue);
      expect(enmascarado.contains('64831'), isFalse);
    });

    test('formatea de forma legible para el dueno del numero', () {
      expect(UtilesTelefono.formatoLegible('+56964831207'), '+56 9 6483 1207');
    });

    test('formatea el numero nacional mientras se escribe', () {
      expect(UtilesTelefono.formatoNacional('9'), '9');
      expect(UtilesTelefono.formatoNacional('9648'), '9 648');
      expect(UtilesTelefono.formatoNacional('964831207'), '9 6483 1207');
    });
  });

  group('UtilesTelefono (Venezuela)', () {
    const pais = PaisTelefono.venezuela;

    test('acepta un movil venezolano escrito de varias formas', () {
      const equivalentes = [
        '4121234567',
        '412 123 4567',
        '+58 412 123 4567',
        '584121234567',
        '00584121234567',
        '0412-123-4567',
      ];

      for (final entrada in equivalentes) {
        expect(
          UtilesTelefono.aE164(entrada, pais),
          '+584121234567',
          reason: 'Fallo con la entrada "$entrada"',
        );
      }
    });

    test('acepta las cinco operadoras moviles venezolanas', () {
      for (final prefijo in ['412', '414', '416', '424', '426']) {
        expect(
          UtilesTelefono.esMovilValido('${prefijo}1234567', pais),
          isTrue,
          reason: 'Fallo con el prefijo $prefijo',
        );
      }
    });

    test('rechaza numeros que no son moviles venezolanos', () {
      expect(UtilesTelefono.esMovilValido('2121234567', pais), isFalse); // fijo
      expect(UtilesTelefono.esMovilValido('412123456', pais), isFalse); // corto
      expect(
        UtilesTelefono.esMovilValido('41212345678', pais),
        isFalse,
      ); // largo
      expect(UtilesTelefono.esMovilValido('', pais), isFalse);
      expect(UtilesTelefono.aE164('2121234567', pais), isNull);
    });

    test('detecta numeros venezolanos obviamente falsos', () {
      expect(UtilesTelefono.pareceSospechoso('4121111111', pais), isTrue);
      expect(UtilesTelefono.pareceSospechoso('4121234567', pais), isTrue);
      expect(UtilesTelefono.pareceSospechoso('4149876543', pais), isFalse);
    });

    test('enmascara sin revelar el numero completo', () {
      final enmascarado = UtilesTelefono.enmascarar('+584121234567');
      expect(enmascarado.contains('67'), isTrue);
      expect(enmascarado.contains('123456'), isFalse);
    });

    test('formatea de forma legible para el dueno del numero', () {
      expect(
        UtilesTelefono.formatoLegible('+584121234567'),
        '+58 412 123 4567',
      );
    });

    test('formatea el numero nacional mientras se escribe', () {
      expect(UtilesTelefono.formatoNacional('4', pais), '4');
      expect(UtilesTelefono.formatoNacional('412123', pais), '412 123');
      expect(
        UtilesTelefono.formatoNacional('4121234567', pais),
        '412 123 4567',
      );
    });

    test('no confunde un numero chileno con uno venezolano', () {
      expect(UtilesTelefono.paisDesde('+56964831207'), PaisTelefono.chile);
      expect(UtilesTelefono.paisDesde('+584121234567'), PaisTelefono.venezuela);
    });
  });
}
