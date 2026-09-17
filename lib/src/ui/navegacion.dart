import 'package:flutter/material.dart';

/// Pantallas de la landing. Cada una tiene su propia direccion para que el
/// boton «atras» del navegador y los links directos funcionen.
enum PaginaOnix {
  inicio('/', 'Inicio'),
  comoFunciona('/como-funciona', 'Cómo funciona'),
  premios('/premios', 'Premios'),
  onixDrive('/onix-drive', 'Onix Drive');

  const PaginaOnix(this.ruta, this.titulo);

  final String ruta;
  final String titulo;

  /// Las que aparecen como enlaces en la barra (el inicio va en el logo y en
  /// el boton «Participar»).
  static const enBarra = [comoFunciona, premios, onixDrive];

  static PaginaOnix? desdeRuta(String? ruta) {
    // La ruta puede traer parametros (`/?inv=...`): solo cuenta el camino.
    final camino = Uri.tryParse(ruta ?? '/')?.path ?? '/';
    for (final pagina in values) {
      if (pagina.ruta == camino) return pagina;
    }
    return camino.isEmpty ? inicio : null;
  }
}

abstract final class NavegacionOnix {
  /// Lleva a [destino]. El inicio queda siempre al fondo de la pila: asi el
  /// formulario o el panel conservan lo que la persona iba escribiendo.
  static void ir(BuildContext contexto, PaginaOnix destino) {
    final navegador = Navigator.of(contexto);
    final actual = ModalRoute.of(contexto)?.settings.name;
    if (PaginaOnix.desdeRuta(actual) == destino) return;

    if (destino == PaginaOnix.inicio) {
      navegador.popUntil((ruta) => ruta.isFirst);
    } else {
      navegador.pushNamedAndRemoveUntil(destino.ruta, (ruta) => ruta.isFirst);
    }
  }
}
