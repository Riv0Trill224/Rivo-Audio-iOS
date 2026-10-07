# Cambios

## 0.2.0 · 2026-10-07

- Estado de letras incrustadas y LRC debajo del título en biblioteca y editor.
- Detección de LRC válido, inválido e ilegible; reconocimiento de `.LRC` existente.
- Detección MP3 SYLT; exportación de tiempos en milisegundos sin modificar el audio.
- Búsqueda y contraste en Genius, token personal en Keychain, consulta web sin token y enlaces a sus letras.
- Contraste automático conservador: sin confirmación se deja la propuesta en Pendientes.
- LRC en la misma carpeta y con el nombre base del audio; protección frente a sobrescritura y recuperación al deshacer.
- Validación segura de rutas basada en directorios existentes, sin falso rechazo de LRC nuevos por alias de iOS.
- Selección persistente de pestañas durante las actualizaciones de biblioteca.
- IPA arm64 para iOS 18+, verificada tras 15 pruebas superadas y un caso omitido en simulador iPhone 13.

## 0.1.0

Editor nativo de metadatos y portadas, indicador Apple de contenido explícito, LRCLIB, MusicBrainz, edición LRC, automatización, selección por lotes e historial.
