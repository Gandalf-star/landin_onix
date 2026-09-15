import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../datos/repositorio_memoria.dart';
import '../datos/repositorio_referidos.dart';
import '../datos/repositorio_supabase.dart';
import 'entorno.dart';

/// De donde terminaron saliendo los datos y por que.
///
/// La landing muestra un distintivo con esta informacion: si el backend no
/// esta disponible es mucho mejor decirlo que mostrar contadores en cero sin
/// explicacion.
@immutable
class ResultadoArranque {
  const ResultadoArranque({
    required this.repositorio,
    required this.origen,
    this.aviso,
  });

  final RepositorioReferidos repositorio;
  final OrigenDatos origen;

  /// Motivo por el que no se pudo usar Supabase, o `null` si se esta usando.
  final String? aviso;

  bool get usaSupabase => origen == OrigenDatos.supabase;
}

/// Prepara la capa de datos antes de dibujar la primera pantalla.
///
/// El arranque nunca falla: si el `.env` no esta, si las credenciales estan
/// incompletas o si a la base todavia le falta el esquema, se cae al
/// repositorio en memoria y se explica el motivo.
Future<ResultadoArranque> arrancar() async {
  await Entorno.cargar();

  if (Entorno.origenDatos == OrigenDatos.memoria) {
    return ResultadoArranque(
      repositorio: RepositorioEnMemoria(),
      origen: OrigenDatos.memoria,
      aviso: Entorno.problema ??
          'ORIGEN_DATOS=memoria en el .env: los datos son de demostración y '
              'se pierden al recargar.',
    );
  }

  try {
    await Supabase.initialize(
      url: Entorno.urlSupabase,
      // El parametro se llamaba `anonKey`; acepta igual la clave publica
      // clasica que entrega el panel de Supabase.
      publishableKey: Entorno.claveAnonima,
      // La sesion la maneja el token propio de la campana, no Supabase Auth.
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  } catch (error) {
    return ResultadoArranque(
      repositorio: RepositorioEnMemoria(),
      origen: OrigenDatos.memoria,
      aviso: 'No se pudo inicializar Supabase ($error). Se usan datos de '
          'demostración.',
    );
  }

  final cliente = Supabase.instance.client;
  final problema = await revisarEsquema(cliente);
  if (problema != null) {
    return ResultadoArranque(
      repositorio: RepositorioEnMemoria(),
      origen: OrigenDatos.memoria,
      aviso: problema,
    );
  }

  return ResultadoArranque(
    repositorio: RepositorioSupabase(cliente),
    origen: OrigenDatos.supabase,
  );
}
