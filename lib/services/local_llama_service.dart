// Conditional export facade choosing the appropriate implementation.
// Web -> local_llama_service_web.dart (stub)
// IO  -> local_llama_service_io.dart (currently also stubbed / simplified)

export 'local_llama_service_web.dart'
  if (dart.library.io) 'local_llama_service_io.dart';

