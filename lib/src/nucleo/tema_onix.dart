import 'package:flutter/material.dart';

/// Paleta oficial de Onix Drive.
///
/// Los tonos se tomaron del tema de la app de produccion
/// (`apps_onix/mobile/lib/core/theme.dart`) para que la landing se vea como
/// una extension natural de la plataforma y no como una pieza suelta.
abstract final class ColoresOnix {
  // Azules Onix
  static const azulOnix = Color(0xFF030E36); // azul principal de marca
  static const azulProfundo = Color(0xFF07102C); // fondos oscuros / hero
  static const azulNoche = Color(0xFF06123A);
  static const azulSuave = Color(0xFF17234B); // superficies sobre el azul
  static const azulElectrico = Color(0xFF061E6D); // acento y gradientes

  // Amarillos Onix
  static const amarilloOnix = Color(0xFFFFC700); // amarillo principal
  static const amarilloIntenso = Color(0xFFFFCC00);
  static const amarilloClaro = Color(0xFFFFF4B8); // fondos suaves
  static const ambar = Color(0xFFFFA000); // extremo calido del gradiente

  // Neutros
  static const fondo = Color(0xFFF6F7FA);
  static const blanco = Color(0xFFFFFFFF);
  static const texto = Color(0xFF10182E);
  static const textoSuave = Color(0xFF778197);
  static const borde = Color(0xFFE2E5EC);
  static const bordeClaro = Color(0xFFE8ECF5);

  // Semanticos
  static const verde = Color(0xFF16A36A);
  static const rojo = Color(0xFFE5484D);

  // Sobre fondo oscuro
  static const sobreAzul = Color(0xFFE8ECF5);
  static const sobreAzulSuave = Color(0xFF9FB0CC);
  static const bordeSobreAzul = Color(0x1FFFFFFF);
}

abstract final class GradientesOnix {
  /// Fondo del hero y de las secciones oscuras.
  static const fondoOscuro = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      ColoresOnix.azulProfundo,
      ColoresOnix.azulOnix,
      ColoresOnix.azulElectrico,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Acento dorado para botones primarios y metricas destacadas.
  static const dorado = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      ColoresOnix.amarilloIntenso,
      ColoresOnix.amarilloOnix,
      ColoresOnix.ambar,
    ],
  );

  static const doradoTexto = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      ColoresOnix.amarilloClaro,
      ColoresOnix.amarilloOnix,
      ColoresOnix.ambar,
    ],
  );
}

/// Espaciados y radios usados en toda la landing.
abstract final class MedidasOnix {
  static const anchoMaximoContenido = 1180.0;
  static const radioChico = 12.0;
  static const radioMedio = 18.0;
  static const radioGrande = 26.0;
  static const radioExtra = 34.0;

  static const espacioSeccionEscritorio = 104.0;
  static const espacioSeccionMovil = 64.0;
}

/// Puntos de quiebre responsivos.
abstract final class PuntosQuiebre {
  /// Telefonos angostos (iPhone SE, Android de entrada): margenes mas justos.
  static const movilChico = 380.0;
  static const movil = 720.0;
  static const tablet = 1024.0;

  /// Desde este ancho la barra superior muestra los enlaces; por debajo usa
  /// el menu de hamburguesa. Va mas alto que [movil] para que los cuatro
  /// enlaces y el boton nunca queden apretados en una tablet vertical.
  static const navegacionCompleta = 900.0;

  static bool esMovilChico(BuildContext contexto) =>
      MediaQuery.sizeOf(contexto).width < movilChico;

  static bool esMovil(BuildContext contexto) =>
      MediaQuery.sizeOf(contexto).width < movil;

  static bool esEscritorio(BuildContext contexto) =>
      MediaQuery.sizeOf(contexto).width >= tablet;
}

const _fuenteTitulos = 'Manrope';
const _fuenteTexto = 'Inter';
const _respaldoFuentes = <String>[
  'Segoe UI',
  'Roboto',
  'Helvetica Neue',
  'Arial',
];

ThemeData construirTemaOnix() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: ColoresOnix.fondo,
    fontFamily: _fuenteTexto,
    fontFamilyFallback: _respaldoFuentes,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ColoresOnix.azulOnix,
      primary: ColoresOnix.azulOnix,
      onPrimary: ColoresOnix.blanco,
      secondary: ColoresOnix.amarilloOnix,
      onSecondary: ColoresOnix.azulOnix,
      surface: ColoresOnix.blanco,
      onSurface: ColoresOnix.texto,
      error: ColoresOnix.rojo,
    ),
  );

  return base.copyWith(
    // Cada estilo se reemplaza entero, asi que lleva su familia y su color:
    // sin color explicito el texto se pintaba blanco sobre las tarjetas
    // blancas (titulos del formulario, de los pasos y de las reglas).
    textTheme: base.textTheme
        .apply(bodyColor: ColoresOnix.texto, displayColor: ColoresOnix.texto)
        .copyWith(
          displayLarge: const TextStyle(
            fontFamily: _fuenteTitulos,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            fontWeight: FontWeight.w800,
            height: 1.04,
            letterSpacing: -1.6,
          ),
          displayMedium: const TextStyle(
            fontFamily: _fuenteTitulos,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            fontWeight: FontWeight.w800,
            height: 1.08,
            letterSpacing: -1.1,
          ),
          headlineLarge: const TextStyle(
            fontFamily: _fuenteTitulos,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.6,
          ),
          headlineMedium: const TextStyle(
            fontFamily: _fuenteTitulos,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.4,
          ),
          titleLarge: const TextStyle(
            fontFamily: _fuenteTitulos,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          bodyLarge: const TextStyle(
            fontFamily: _fuenteTexto,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            height: 1.6,
            fontSize: 16.5,
          ),
          bodyMedium: const TextStyle(
            fontFamily: _fuenteTexto,
            fontFamilyFallback: _respaldoFuentes,
            color: ColoresOnix.texto,
            height: 1.6,
            fontSize: 15,
          ),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ColoresOnix.azulOnix,
        foregroundColor: ColoresOnix.blanco,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        ),
        textStyle: const TextStyle(
          fontFamily: _fuenteTitulos,
          fontFamilyFallback: _respaldoFuentes,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ColoresOnix.azulOnix,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        side: const BorderSide(color: ColoresOnix.borde, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        ),
        textStyle: const TextStyle(
          fontFamily: _fuenteTitulos,
          fontFamilyFallback: _respaldoFuentes,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ColoresOnix.azulOnix,
        textStyle: const TextStyle(
          fontFamily: _fuenteTexto,
          fontFamilyFallback: _respaldoFuentes,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ColoresOnix.blanco,
      hintStyle: const TextStyle(color: ColoresOnix.textoSuave),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        borderSide: const BorderSide(color: ColoresOnix.borde, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        borderSide: const BorderSide(color: ColoresOnix.borde, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        borderSide:
            const BorderSide(color: ColoresOnix.amarilloOnix, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        borderSide: const BorderSide(color: ColoresOnix.rojo, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
        borderSide: const BorderSide(color: ColoresOnix.rojo, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(color: ColoresOnix.borde, space: 1),
    cardTheme: CardThemeData(
      color: ColoresOnix.blanco,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioGrande),
        side: const BorderSide(color: ColoresOnix.borde),
      ),
    ),
    // La barra de desplazamiento por defecto es gris oscuro y sobre el azul
    // de la pagina no se ve: va en amarillo Onix sobre un riel oscuro, que
    // se distingue tanto en las secciones azules como en las claras.
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.hovered) ||
                estados.contains(WidgetState.dragged)
            ? 12
            : 9,
      ),
      radius: const Radius.circular(8),
      crossAxisMargin: 2,
      minThumbLength: 48,
      thumbColor: WidgetStateProperty.resolveWith(
        (estados) => estados.contains(WidgetState.hovered) ||
                estados.contains(WidgetState.dragged)
            ? ColoresOnix.amarilloOnix
            : ColoresOnix.amarilloOnix.withValues(alpha: 0.8),
      ),
      trackColor: WidgetStatePropertyAll(
        ColoresOnix.azulProfundo.withValues(alpha: 0.55),
      ),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ColoresOnix.azulOnix,
      contentTextStyle: const TextStyle(
        color: ColoresOnix.blanco,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MedidasOnix.radioMedio),
      ),
    ),
  );
}
