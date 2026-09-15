import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// De donde salen los datos de la campana.
enum OrigenDatos {
  /// Proyecto Supabase real.
  supabase,

  /// Datos de demostracion en memoria, sin backend.
  memoria,
}

/// Lectura tipada del archivo `.env`.
///
/// Se carga una sola vez al arrancar. Si el archivo falta o esta incompleto la
/// aplicacion no se cae: cae al modo memoria y deja el motivo en [problema],
/// que la interfaz muestra como aviso.
abstract final class Entorno {
  static bool _cargado = false;
  static String? _problema;

  /// Motivo por el que no se pudo usar Supabase, o `null` si todo esta bien.
  static String? get problema => _problema;

  static Future<void> cargar() async {
    if (_cargado) return;
    try {
      await dotenv.load(fileName: '.env');
    } catch (error) {
      _problema = 'No se encontro el archivo .env; se usaran datos de '
          'demostracion.';
      if (kDebugMode) debugPrint('Entorno: $error');
    }
    _cargado = true;

    if (_problema == null && (urlSupabase.isEmpty || claveAnonima.isEmpty)) {
      _problema = 'Faltan SUPABASE_URL o SUPABASE_ANON_KEY en el .env; se '
          'usaran datos de demostracion.';
    }
  }

  static String _leer(String clave, {String pordefecto = ''}) {
    if (!_cargado) return pordefecto;
    return dotenv.env[clave]?.trim() ?? pordefecto;
  }

  static String get urlSupabase => _leer('SUPABASE_URL');

  static String get claveAnonima => _leer('SUPABASE_ANON_KEY');

  /// Origen pedido en el `.env`, degradado a [OrigenDatos.memoria] si las
  /// credenciales no estan completas.
  static OrigenDatos get origenDatos {
    if (_problema != null) return OrigenDatos.memoria;
    return _leer('ORIGEN_DATOS', pordefecto: 'supabase').toLowerCase() ==
            'memoria'
        ? OrigenDatos.memoria
        : OrigenDatos.supabase;
  }

  static bool get hayCredenciales =>
      urlSupabase.isNotEmpty && claveAnonima.isNotEmpty;
}
