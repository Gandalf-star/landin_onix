import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'datos/controlador_referidos.dart';
import 'nucleo/arranque.dart';
import 'nucleo/config_campana.dart';
import 'nucleo/tema_onix.dart';
import 'ui/pagina_landing.dart';

/// Deja el [ControladorReferidos] disponible para todo el arbol de widgets.
///
/// Se usa [InheritedNotifier] en vez de un paquete externo: el estado de esta
/// landing es pequeno y asi el proyecto queda sin dependencias extra.
class ProveedorCampana extends InheritedNotifier<ControladorReferidos> {
  const ProveedorCampana({
    super.key,
    required ControladorReferidos controlador,
    required super.child,
  }) : super(notifier: controlador);

  static ControladorReferidos de(BuildContext contexto) {
    final proveedor = contexto
        .dependOnInheritedWidgetOfExactType<ProveedorCampana>();
    assert(proveedor != null, 'Falta ProveedorCampana sobre este widget');
    return proveedor!.notifier!;
  }

  /// Acceso sin suscribirse a los cambios (para llamar acciones).
  static ControladorReferidos accion(BuildContext contexto) {
    final proveedor = contexto
        .getInheritedWidgetOfExactType<ProveedorCampana>();
    assert(proveedor != null, 'Falta ProveedorCampana sobre este widget');
    return proveedor!.notifier!;
  }
}

class AplicacionOnix extends StatefulWidget {
  const AplicacionOnix({super.key, required this.arranque});

  /// Capa de datos ya resuelta: Supabase si esta disponible, memoria si no.
  final ResultadoArranque arranque;

  @override
  State<AplicacionOnix> createState() => _AplicacionOnixState();
}

class _AplicacionOnixState extends State<AplicacionOnix> {
  late final ControladorReferidos _controlador;

  @override
  void initState() {
    super.initState();
    // El repositorio ya viene elegido desde arrancar(): la interfaz no
    // sabe ni necesita saber si detras hay Supabase o datos en memoria.
    _controlador = ControladorReferidos(widget.arranque.repositorio)
      ..inicializar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProveedorCampana(
      controlador: _controlador,
      child: MaterialApp(
        title: '${ConfigCampana.nombreCampana} · ${ConfigCampana.nombreMarca}',
        debugShowCheckedModeBanner: false,
        theme: construirTemaOnix(),
        scrollBehavior: const _DesplazamientoWeb(),
        home: PaginaLanding(arranque: widget.arranque),
      ),
    );
  }
}

/// Permite arrastrar con el mouse, util al probar la web en escritorio.
class _DesplazamientoWeb extends MaterialScrollBehavior {
  const _DesplazamientoWeb();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
