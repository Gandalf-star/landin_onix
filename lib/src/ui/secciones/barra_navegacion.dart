import 'package:flutter/material.dart';

import '../../app.dart';
import '../../nucleo/config_campana.dart';
import '../../nucleo/tema_onix.dart';
import '../componentes/logo_onix.dart';
import '../navegacion.dart';

/// Barra superior fija. Arranca transparente sobre el encabezado oscuro y se
/// vuelve solida apenas la persona empieza a bajar. Cada enlace abre su
/// propia pantalla; la actual queda resaltada.
class BarraNavegacion extends StatefulWidget {
  const BarraNavegacion({
    super.key,
    required this.desplazador,
    required this.paginaActual,
  });

  final ScrollController desplazador;
  final PaginaOnix paginaActual;

  @override
  State<BarraNavegacion> createState() => _BarraNavegacionState();
}

class _BarraNavegacionState extends State<BarraNavegacion> {
  bool _compacta = false;

  @override
  void initState() {
    super.initState();
    widget.desplazador.addListener(_alDesplazar);
  }

  @override
  void dispose() {
    widget.desplazador.removeListener(_alDesplazar);
    super.dispose();
  }

  void _alDesplazar() {
    if (!widget.desplazador.hasClients) return;
    final compacta = widget.desplazador.offset > 60;
    if (compacta != _compacta) setState(() => _compacta = compacta);
  }

  @override
  Widget build(BuildContext context) {
    final esMovil = PuntosQuiebre.esMovil(context);
    final conEnlaces = MediaQuery.sizeOf(context).width >=
        PuntosQuiebre.navegacionCompleta;
    final controlador = ProveedorCampana.de(context);

    void irA(PaginaOnix pagina) => NavegacionOnix.ir(context, pagina);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      height: _compacta ? 70 : 88,
      // Mismo margen lateral que las secciones: el logo queda alineado con
      // el contenido de la pagina.
      padding: EdgeInsets.symmetric(
        horizontal: PuntosQuiebre.esMovilChico(context)
            ? 16
            : (esMovil ? 20 : 32),
      ),
      decoration: BoxDecoration(
        color: _compacta
            ? ColoresOnix.azulProfundo.withValues(alpha: 0.96)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: _compacta ? ColoresOnix.bordeSobreAzul : Colors.transparent,
          ),
        ),
        boxShadow: _compacta
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MedidasOnix.anchoMaximoContenido,
          ),
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => irA(PaginaOnix.inicio),
                  child: LogoOnix(
                    alto: _compacta ? 32 : 38,
                    sobreFondoOscuro: true,
                  ),
                ),
              ),
              const Spacer(),
              if (conEnlaces) ...[
                for (final pagina in PaginaOnix.enBarra)
                  _EnlaceNavegacion(
                    texto: pagina.titulo,
                    activo: pagina == widget.paginaActual,
                    alPresionar: () => irA(pagina),
                  ),
                const SizedBox(width: 14),
                _BotonParticipar(
                  texto: controlador.haySesion ? 'Mi panel' : 'Participar',
                  alPresionar: () => irA(PaginaOnix.inicio),
                ),
              ] else
                _MenuMovil(
                  paginaActual: widget.paginaActual,
                  alElegir: irA,
                  textoParticipar: controlador.haySesion
                      ? 'Ir a mi panel'
                      : 'Participar en ${ConfigCampana.nombreCampana}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnlaceNavegacion extends StatefulWidget {
  const _EnlaceNavegacion({
    required this.texto,
    required this.activo,
    required this.alPresionar,
  });

  final String texto;
  final bool activo;
  final VoidCallback alPresionar;

  @override
  State<_EnlaceNavegacion> createState() => _EnlaceNavegacionState();
}

class _EnlaceNavegacionState extends State<_EnlaceNavegacion> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final resaltado = _encima || widget.activo;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.alPresionar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.texto,
                style: TextStyle(
                  color: resaltado
                      ? ColoresOnix.amarilloOnix
                      : ColoresOnix.sobreAzul,
                  fontSize: 14.5,
                  fontWeight: widget.activo ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: resaltado ? 22 : 0,
                decoration: BoxDecoration(
                  color: ColoresOnix.amarilloOnix,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonParticipar extends StatelessWidget {
  const _BotonParticipar({
    required this.texto,
    required this.alPresionar,
    this.anchoCompleto = false,
  });

  final String texto;
  final VoidCallback alPresionar;

  /// En el menu del celular ocupa todo el ancho con el texto centrado.
  final bool anchoCompleto;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: alPresionar,
        child: Container(
          alignment: anchoCompleto ? Alignment.center : null,
          padding: EdgeInsets.symmetric(
            horizontal: 22,
            vertical: anchoCompleto ? 16 : 13,
          ),
          decoration: BoxDecoration(
            gradient: GradientesOnix.dorado,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            texto,
            style: const TextStyle(
              fontFamily: 'Manrope',
              color: ColoresOnix.azulOnix,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuMovil extends StatelessWidget {
  const _MenuMovil({
    required this.paginaActual,
    required this.alElegir,
    required this.textoParticipar,
  });

  final PaginaOnix paginaActual;
  final ValueChanged<PaginaOnix> alElegir;
  final String textoParticipar;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded, color: ColoresOnix.blanco),
      tooltip: 'Menú',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: ColoresOnix.azulProfundo,
        // En celulares bajos (o acostados) el menu no cabe en el 56 % de la
        // pantalla que usa por defecto: puede crecer y desplazarse.
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MedidasOnix.radioExtra),
          ),
        ),
        builder: (contexto) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: ColoresOnix.bordeSobreAzul,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                for (final pagina in PaginaOnix.values)
                  ListTile(
                    title: Text(
                      pagina.titulo,
                      style: TextStyle(
                        color: pagina == paginaActual
                            ? ColoresOnix.amarilloOnix
                            : ColoresOnix.sobreAzul,
                        fontSize: 16,
                        fontWeight: pagina == paginaActual
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    trailing: Icon(
                      pagina == paginaActual
                          ? Icons.circle
                          : Icons.chevron_right_rounded,
                      size: pagina == paginaActual ? 9 : 24,
                      color: pagina == paginaActual
                          ? ColoresOnix.amarilloOnix
                          : ColoresOnix.sobreAzulSuave,
                    ),
                    onTap: () {
                      Navigator.of(contexto).pop();
                      alElegir(pagina);
                    },
                  ),
                const SizedBox(height: 14),
                _BotonParticipar(
                  anchoCompleto: true,
                  texto: textoParticipar,
                  alPresionar: () {
                    Navigator.of(contexto).pop();
                    alElegir(PaginaOnix.inicio);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
