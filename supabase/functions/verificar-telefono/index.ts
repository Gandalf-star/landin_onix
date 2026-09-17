// =====================================================================
//  Reto 50 Onix · Edge Function `verificar-telefono`
//
//  Confirma con Twilio Verify que el teléfono con el que alguien crea su
//  cuenta existe y es suyo. Solo se usa al CREAR UNA CUENTA (quien invita):
//  para iniciar sesión se usa el celular y la contraseña, y quien recibe
//  una invitación valida su código sin SMS (`invitado_validar_codigo`).
//
//  Acciones (POST con JSON `{ "accion": ... }`):
//    - iniciar_registro  valida los datos de la cuenta, guarda el registro
//                        pendiente y pide a Twilio que envíe el SMS.
//    - reenviar          vuelve a enviar el código del registro.
//    - confirmar         revisa el código con Twilio y, si lo aprueba,
//                        crea la cuenta y abre la sesión.
//    - estado            diagnóstico: dice si Twilio está configurado.
//
//  Por qué existe esta función
//  ---------------------------
//  Las credenciales de Twilio no pueden viajar al navegador: cualquiera
//  podría usarlas para mandar SMS a nuestro costo. Viven como secretos de
//  esta función, y las funciones SQL del registro solo aceptan llamadas
//  con la service_role, que tampoco sale de aquí.
//
//  Secretos (supabase secrets set ...):
//    TWILIO_ACCOUNT_SID          AC...  (cuenta PROPIA de la landing)
//    TWILIO_AUTH_TOKEN           token de esa cuenta
//    TWILIO_VERIFY_SERVICE_SID   VA...  servicio de Verify
//    TWILIO_CANAL                opcional: sms (por defecto) o whatsapp
//    TWILIO_VALIDAR_TIPO_LINEA   opcional: true para rechazar números
//                                VoIP o fijos con Twilio Lookup (tiene
//                                costo por consulta)
//  SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase solo.
//
//  Contrato de respuesta: siempre JSON. Los errores de negocio viajan como
//  `{ "error": { "motivo", "mensaje" } }`, el mismo formato que devuelven
//  las funciones SQL, y el cliente Dart los convierte en ErrorReferidos.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const cabecerasCors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json = Record<string, unknown>;

// ---------------------------------------------------------------------
// Configuración
// ---------------------------------------------------------------------

const configTwilio = {
  cuenta: Deno.env.get("TWILIO_ACCOUNT_SID") ?? "",
  token: Deno.env.get("TWILIO_AUTH_TOKEN") ?? "",
  servicio: Deno.env.get("TWILIO_VERIFY_SERVICE_SID") ?? "",
  canal: (Deno.env.get("TWILIO_CANAL") ?? "sms").trim().toLowerCase(),
  validarTipoLinea:
    (Deno.env.get("TWILIO_VALIDAR_TIPO_LINEA") ?? "").trim().toLowerCase() ===
      "true",
};

const twilioConfigurado = () =>
  configTwilio.cuenta.startsWith("AC") &&
  configTwilio.token.length > 0 &&
  configTwilio.servicio.startsWith("VA");

const base = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// ---------------------------------------------------------------------
// Respuestas
// ---------------------------------------------------------------------

function responder(cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: {
      ...cabecerasCors,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function error(motivo: string, mensaje: string, estado = 200): Response {
  return responder({ error: { motivo, mensaje } }, estado);
}

const sinServicioSms = () =>
  error(
    "servicioSmsNoDisponible",
    "La verificación por SMS no está disponible en este momento. Intenta más tarde.",
  );

function esError(valor: unknown): valor is { error: Json } {
  return typeof valor === "object" && valor !== null && "error" in valor;
}

// ---------------------------------------------------------------------
// Base de datos
// ---------------------------------------------------------------------

async function rpc(funcion: string, parametros: Json): Promise<unknown> {
  const { data, error: fallo } = await base.rpc(funcion, parametros);
  if (fallo) {
    console.error(`[${funcion}]`, fallo.message);
    throw new Error(`Falló ${funcion}`);
  }
  return data;
}

// ---------------------------------------------------------------------
// Twilio
// ---------------------------------------------------------------------

type RespuestaTwilio = { ok: boolean; estado: number; cuerpo: Json };

async function llamarTwilio(
  url: string,
  campos: Record<string, string>,
  metodo: "GET" | "POST" = "POST",
): Promise<RespuestaTwilio> {
  const credenciales = btoa(`${configTwilio.cuenta}:${configTwilio.token}`);
  const respuesta = await fetch(url, {
    method: metodo,
    headers: {
      Authorization: `Basic ${credenciales}`,
      ...(metodo === "POST"
        ? { "Content-Type": "application/x-www-form-urlencoded" }
        : {}),
    },
    body: metodo === "POST" ? new URLSearchParams(campos) : undefined,
  });
  const cuerpo = await respuesta.json().catch(() => ({})) as Json;
  return { ok: respuesta.ok, estado: respuesta.status, cuerpo };
}

const urlVerify = (recurso: string) =>
  `https://verify.twilio.com/v2/Services/${configTwilio.servicio}/${recurso}`;

/** Pide a Twilio Verify que envíe (o reenvíe) el código al teléfono. */
async function enviarCodigo(telefono: string): Promise<Response | null> {
  const r = await llamarTwilio(urlVerify("Verifications"), {
    To: telefono,
    Channel: configTwilio.canal,
    Locale: "es",
  });
  if (r.ok) return null;

  const codigo = Number(r.cuerpo.code);
  console.error("[Twilio Verifications]", r.estado, codigo, r.cuerpo.message);

  switch (codigo) {
    case 60200: // parámetro inválido (número mal formado)
    case 21211:
    case 21614: // el número no puede recibir SMS
    case 60205: // SMS no soportado (línea fija)
      return error(
        "telefonoInvalido",
        "No pudimos enviar el SMS a ese número. Revisa que sea tu celular.",
      );
    case 60410: // bloqueado por Fraud Guard de Twilio
    case 60605:
      return error(
        "numeroSospechoso",
        "No podemos enviar códigos a ese número. Usa tu número personal.",
      );
    case 60203: // demasiados envíos al mismo número
    case 60212:
    case 20429:
      return error(
        "demasiadosIntentos",
        "Pediste demasiados códigos. Espera unos minutos e intenta de nuevo.",
      );
    default:
      return sinServicioSms();
  }
}

/** `true` si Twilio aprueba el código, `false` si no coincide. */
async function revisarCodigo(
  telefono: string,
  codigo: string,
): Promise<boolean | Response> {
  const r = await llamarTwilio(urlVerify("VerificationCheck"), {
    To: telefono,
    Code: codigo,
  });
  if (r.ok) return r.cuerpo.status === "approved";

  const codigoTwilio = Number(r.cuerpo.code);
  console.error("[Twilio VerificationCheck]", r.estado, codigoTwilio);

  // 404 / 20404: Twilio ya no tiene esa verificación (venció, se aprobó o
  // agotó sus intentos). 60202: demasiados intentos para ese código.
  if (r.estado === 404 || codigoTwilio === 20404) {
    return error("verificacionExpirada", "El código expiró. Pide uno nuevo.");
  }
  if (codigoTwilio === 60202) {
    return error(
      "demasiadosIntentos",
      "Demasiados intentos fallidos. Pide un código nuevo.",
    );
  }
  return sinServicioSms();
}

/**
 * Twilio Lookup: rechaza números VoIP y fijos antes de gastar un SMS.
 * Si la consulta falla no se bloquea a nadie: es una capa extra, no la
 * única defensa.
 */
async function revisarTipoLinea(telefono: string): Promise<Response | null> {
  if (!configTwilio.validarTipoLinea) return null;
  try {
    const r = await llamarTwilio(
      `https://lookups.twilio.com/v2/PhoneNumbers/${
        encodeURIComponent(telefono)
      }?Fields=line_type_intelligence`,
      {},
      "GET",
    );
    const tipo = (r.cuerpo.line_type_intelligence as Json | undefined)?.type;
    if (r.ok && typeof tipo === "string") {
      if (["nonFixedVoip", "fixedVoip"].includes(tipo)) {
        return error(
          "numeroSospechoso",
          "Los números virtuales no pueden participar. Usa tu celular personal.",
        );
      }
      if (["landline", "tollFree", "premium", "sharedCost"].includes(tipo)) {
        return error(
          "telefonoInvalido",
          "Ese número no es un celular. Usa tu número móvil personal.",
        );
      }
    }
  } catch (e) {
    console.error("[Twilio Lookup]", e);
  }
  return null;
}

// ---------------------------------------------------------------------
// Acciones
// ---------------------------------------------------------------------

function texto(valor: unknown): string | null {
  return typeof valor === "string" ? valor : null;
}

/** Detalle del dispositivo que manda la landing (la base lo depura). */
function objeto(valor: unknown): Json | null {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor)
    ? valor as Json
    : null;
}

function ipDe(peticion: Request): string | null {
  const reenviada = peticion.headers.get("x-forwarded-for");
  return reenviada?.split(",")[0]?.trim() ||
    peticion.headers.get("x-real-ip") ||
    null;
}

/** Funciones SQL de cada paso de un flujo que pasa por un SMS. */
type Flujo = {
  preparar: string;
  anular: string;
  prepararReenvio: string;
  paraVerificar: string;
  registrarFallo: string;
  completar: string;
};

const flujoRegistro: Flujo = {
  preparar: "cuenta_preparar_registro",
  anular: "cuenta_anular_envio",
  prepararReenvio: "cuenta_preparar_reenvio",
  paraVerificar: "cuenta_registro_para_verificar",
  registrarFallo: "cuenta_registrar_fallo",
  completar: "cuenta_completar_registro",
};

/** Deja lista la espera en la base y, si todo está en orden, envía el SMS. */
async function iniciar(flujo: Flujo, parametros: Json) {
  if (!twilioConfigurado()) return sinServicioSms();

  const pendiente = await rpc(flujo.preparar, parametros);
  if (esError(pendiente)) return responder(pendiente);

  const desafio = pendiente as Json;
  const telefono = desafio.telefono_e164 as string;

  const rechazo = (await revisarTipoLinea(telefono)) ??
    (await enviarCodigo(telefono));
  if (rechazo) {
    // El SMS no salió: esa espera no debe contar para los límites.
    await rpc(flujo.anular, { p_id: desafio.id });
    return rechazo;
  }
  return responder(desafio);
}

async function iniciarRegistro(datos: Json, peticion: Request) {
  return await iniciar(flujoRegistro, {
    p_nombre: texto(datos.nombre),
    p_contrasena: texto(datos.contrasena),
    p_telefono: texto(datos.telefono),
    // El registro no canjea códigos: los invitados validan el suyo sin
    // cuenta ni SMS.
    p_codigo_invitador: null,
    p_huella: texto(datos.huella),
    p_ip: ipDe(peticion),
    p_dispositivo: objeto(datos.dispositivo),
  });
}

async function reenviar(flujo: Flujo, datos: Json) {
  if (!twilioConfigurado()) return sinServicioSms();

  const desafio = await rpc(flujo.prepararReenvio, {
    p_id: texto(datos.id),
  });
  if (esError(desafio)) return responder(desafio);

  const fallo = await enviarCodigo((desafio as Json).telefono_e164 as string);
  return fallo ?? responder(desafio);
}

async function confirmar(flujo: Flujo, datos: Json) {
  if (!twilioConfigurado()) return sinServicioSms();

  const id = texto(datos.id);
  const codigo = (texto(datos.codigo) ?? "").replace(/\D/g, "");
  if (codigo.length < 4 || codigo.length > 10) {
    return error(
      "codigoVerificacionIncorrecto",
      "Escribe el código completo que te llegó por SMS.",
    );
  }

  const pendiente = await rpc(flujo.paraVerificar, { p_id: id });
  if (esError(pendiente)) return responder(pendiente);

  const aprobado = await revisarCodigo(
    (pendiente as Json).telefono_e164 as string,
    codigo,
  );
  if (aprobado instanceof Response) return aprobado;

  if (!aprobado) {
    return responder(await rpc(flujo.registrarFallo, { p_id: id }));
  }
  return responder(await rpc(flujo.completar, { p_id: id }));
}

// ---------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------

Deno.serve(async (peticion) => {
  if (peticion.method === "OPTIONS") {
    return new Response("ok", { headers: cabecerasCors });
  }
  if (peticion.method !== "POST") {
    return error("desconocido", "Método no permitido.", 405);
  }

  let datos: Json;
  try {
    datos = await peticion.json();
  } catch {
    return error("desconocido", "La solicitud no es un JSON válido.", 400);
  }

  try {
    switch (datos.accion) {
      case "iniciar_registro":
        return await iniciarRegistro(datos, peticion);
      case "reenviar":
        return await reenviar(flujoRegistro, datos);
      case "confirmar":
        return await confirmar(flujoRegistro, datos);
      case "estado":
        return responder({
          twilio_configurado: twilioConfigurado(),
          canal: configTwilio.canal,
          valida_tipo_linea: configTwilio.validarTipoLinea,
        });
      default:
        return error("desconocido", "Acción desconocida.", 400);
    }
  } catch (e) {
    console.error("[verificar-telefono]", e);
    return error(
      "desconocido",
      "Algo falló de nuestro lado. Intenta de nuevo.",
      500,
    );
  }
});
