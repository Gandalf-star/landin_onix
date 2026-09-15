{{flutter_js}}
{{flutter_build_config}}

// Arranque sin service worker: la landing no guarda copias en el navegador,
// asi cada visita carga la ultima version publicada. Quien tenga registrado
// un service worker de una version anterior lo pierde solo, porque Flutter
// sigue publicando flutter_service_worker.js, que se desregistra al activarse.
_flutter.loader.load();
