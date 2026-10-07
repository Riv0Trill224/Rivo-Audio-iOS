# Rivo Metadata Editor 0.2.0

App nativa iOS 18+, compilada mediante Xcode en GitHub Actions. Identificador `com.riv0trill.rivometadataeditor`. IPA para dispositivo arm64, sin firma, destinada a SideStore/AltStore.

## Cambios de esta versión

- Estado de letra incrustada y archivo LRC debajo del título en biblioteca y editor. Se distinguen LRC sincronizado, sin tiempos válidos, ilegible y ausente.
- Letras incrustadas leídas mediante TagLib: LYRICS/USLT/©lyr/Vorbis; MP3 SYLT con tiempos en milisegundos se puede exportar a LRC. SYLT con tiempos en frames se detecta pero no se convierte a milisegundos sin un cálculo específico.
- LRCLIB proporciona las letras sincronizadas. Genius es una segunda fuente para comprobar título/artista y consultar la letra en su página. Su API integrada requiere un Client Access Token guardado en Keychain. La consulta web funciona sin token.
- El contraste Genius está activado inicialmente para descargas automáticas. Si no hay token, no hay coincidencia o falla el servicio, se conserva la propuesta en Pendientes. El usuario puede seleccionar el LRC manualmente o desactivar el contraste. La coincidencia de identidad no garantiza igualdad de letras ni sincronización.
- Si ya hay letra sincronizada incrustada y no hay LRC, se exporta junto al audio. Texto incrustado sin tiempos no se convierte artificialmente a sincronizado.
- Comparación de rutas por componentes y directorios existentes resueltos; se mantiene la URL original que tiene el permiso de Archivos. Se elimina el falso rechazo para LRC nuevos y alias `/private/var`. Se rechazan rutas relativas que escapan y enlaces simbólicos externos.
- El LRC utiliza el mismo directorio y nombre base del audio, incluso en subcarpetas y con Unicode. También se reconoce `.LRC` existente; se conserva y solo se reemplaza con su hash y confirmación. Historial permite deshacer.

## Validación

El CI ejecuta pruebas del puente en seis formatos, casos de identidad/versiones de canciones, decodificación Genius, estados de letras, exportación real en subcarpetas, alias de rutas, enlaces externos, protección de LRC existente y deshacer. La navegación se prueba en simulador iPhone 13. La IPA solo se empaqueta si las pruebas pasan.

La prueba física en iPhone y los distintos proveedores de iCloud/Archivos siguen pendientes. El test de alias `/private/var` se omite explícitamente si el sistema no dispone de ese alias. Las pruebas de Genius validan respuestas de muestra; hace falta un token del usuario para verificar el servicio autenticado en vivo.

## GitHub

El proyecto contiene un workflow independiente en `.github/workflows/build-ios.yml`. La compilación provisional usa la rama aislada `codex/rivo-metadata-editor-ipa-20261007` de Rivo-Audio-iOS. Su main no se modifica. La publicación en un repositorio nuevo requiere crear primero `Rivo-Metadata-Editor-iOS`; el conector GitHub disponible no tiene una operación para crear repositorios.
