# Rivo Metadata Editor · iOS

Editor nativo para canciones almacenadas como archivos en el iPhone o iCloud Drive. Interfaz SwiftUI con la paleta de Rivo Audio iOS y Liquid Glass nativo en iOS 26 o posterior; compatible desde iOS 18. Identificador: `com.riv0trill.rivometadataeditor`.

## Versión 0.2.0

IPA nativa para iOS, sin firma para instalar mediante SideStore/AltStore. El CI compila con Xcode y ejecuta pruebas en simulador iPhone 13 antes de empaquetar. La versión 0.2.0 superó compilación y 15 pruebas en simulador (un caso de alias no disponible se omitió). [Ejecución verificada](https://github.com/Riv0Trill224/Rivo-Audio-iOS/actions/runs/37620877949). La IPA es para iPhone arm64, mínimo iOS 18.0, versión 0.2.0/build 2. Consulta `docs/ESTADO.md` para límites y detalles.

### Letras y segundo motor

Debajo del título se muestran por separado la letra incrustada y el LRC vecino: presente y sincronizado, sin tiempos válidos, ilegible o ausente. Lee LYRICS/USLT/©lyr/Vorbis y detecta SYLT en MP3. Puede exportar SYLT en milisegundos o LRC incrustado; no inventa tiempos para texto sin sincronizar.

LRCLIB proporciona LRC. Genius permite buscar una segunda coincidencia y consultar su letra. En Ajustes puedes guardar tu **Client Access Token** de Genius en el Keychain del iPhone, o usar la búsqueda web sin token. No hay un token compartido incluido en el proyecto. Su API se usa para título/artista y enlaces, no para descargar un supuesto LRC de Genius.

La automatización exige por defecto contraste de título/artista con Genius además de los controles de versión, álbum y duración de LRCLIB. Sin confirmación se deja la canción en Pendientes para selección manual. Puedes desactivar el contraste. Ningún porcentaje garantiza que dos versiones tengan los mismos tiempos.

El LRC se guarda **en la carpeta original del audio**, con su mismo nombre base. La validación de rutas preserva el permiso de la carpeta y resuelve correctamente alias de iOS y archivos nuevos. No sobrescribe un LRC existente sin abrirlo y confirmar. `Song.LRC` también se reconoce.

## Funciones implementadas en el código

- Selector de carpetas; acceso persistente mediante bookmarks y escaneo recursivo sin duplicar la misma ubicación.
- Editor individual y por lotes: título, artista, álbum, artista del álbum, fecha, género, pista/disco, compositor, comentario, ISRC, letras incrustadas e identificadores MusicBrainz.
- **Sin clasificar / Explícito / Versión limpia**. M4A/MP4 usa `rtng` con 0/1/2; MP3 utiliza `TXXX:ITUNESADVISORY`; FLAC/Ogg utilizan `ITUNESADVISORY` en Vorbis Comments. Los formatos restantes usan el mapeo de TagLib cuando lo admiten. No es una valoración con estrellas. La insignia E de otro reproductor depende de que lea esa etiqueta; no se promete una insignia universal en MP3 ni se convierten archivos a M4A automáticamente.
- MusicBrainz para buscar datos; elección explícita de edición del álbum. Cover Art Archive para portadas. Importación desde Fotos/Archivos, enlace HTTPS directo y búsqueda manual de imágenes en Google.
- LRCLIB `/api/get` y `/api/search`; letras sincronizadas escritas junto al audio con el mismo nombre base, por ejemplo `Tema.mp3` → `Tema.lrc`.
- Automatización para toda la biblioteca o solo la selección. Conserva las letras existentes y completa solo metadatos vacíos cuando la coincidencia es segura y la edición no es ambigua.
- Barra de progreso, canción actual, recuentos, ETA basado en las últimas doce canciones, detener y reanudar omitiendo letras ya guardadas.
- Pendientes persistentes para versiones dudosas, ausencia de resultados o errores de red. Vista previa de letra y selección manual.
- Editor LRC con texto, cabeceras y desplazamiento de todos los tiempos de ±100/500 ms; reproductor local para comprobar la sincronización.
- Escritura mediante copia temporal, verificación de etiquetas y duración, recuperación local, coordinación de archivos, detección de cambios externos e historial para deshacer.
- Modo solo analizar que genera propuestas sin modificar audio ni LRC.
- Caché local de consultas y portada, pausa entre solicitudes y reintentos limitados ante HTTP 429/503.

## Generar la IPA desde Windows usando GitHub

1. Crea un repositorio nuevo **vacío**, llamado `Rivo-Metadata-Editor-iOS`, en tu cuenta. Puede ser privado. No actives la creación inicial de README/licencia porque estos archivos ya se incluyen.
2. Extrae el ZIP. En la carpeta que contiene `project.yml` sube todos los archivos del proyecto al repositorio, incluyendo `.github/workflows/build-ios.yml` y los archivos de `Vendor/`.
3. Si tienes Git instalado, abre PowerShell en esa carpeta y ejecuta:

   ```powershell
   git init -b main
   git add .
   git commit -m "Start Rivo Metadata Editor iOS"
   git remote add origin https://github.com/Riv0Trill224/Rivo-Metadata-Editor-iOS.git
   git push -u origin main
   ```

4. El push inicia automáticamente **Actions → Rivo Metadata Editor IPA**. El flujo compila TagLib para iPhone/simulador, genera el proyecto, ejecuta las pruebas en iPhone 13 y empaqueta la IPA solamente si pasan.
5. En una ejecución exitosa descarga el artefacto **RivoMetadataEditor-v0.2.0-unsigned**. Extrae su ZIP: dentro estará **RivoMetadataEditor-v0.2.0-unsigned.ipa**.
6. Importa la IPA en SideStore, que aplica la firma personal e instala la app. Esta entrega no incluye certificados ni modifica tu cuenta de Apple.

Si la compilación falla, la app aún no está lista para instalar. Conserva el enlace de la ejecución y revisa el primer error real; el proyecto incluye un artefacto de resultados de pruebas.

## Compilar en un Mac

Instala Xcode con SDK iOS 26 o posterior, acepta su licencia y completa su primera inicialización. Después:

```bash
brew install cmake xcodegen
bash scripts/build-ipa.sh
```

La salida será `dist/RivoMetadataEditor-v0.2.0-unsigned.ipa`. Para ejecutar desde Xcode abre el `.xcodeproj` generado, selecciona tu equipo de firma y un dispositivo/simulador. El código usa APIs de iOS 26 dentro de una comprobación de disponibilidad.

## Usar la primera compilación

1. Biblioteca → Seleccionar carpeta. Elige una ubicación que contenga archivos reales, por ejemplo una carpeta musical de **En mi iPhone** o **iCloud Drive**.
2. Toca una canción. Edita campos, elige clasificación explícita o portada, y presiona Guardar. Los resultados de MusicBrainz se cargan primero como propuesta editable.
3. Automatizar → Iniciar automatización. La selección activa se respeta; sin selección procesa toda la biblioteca. Mantén la app abierta durante el lote.
4. Revisa Pendientes al terminar; visualiza y elige una letra sincronizada. Si ya tienes una letra, ábrela en el editor y guarda con confirmación para reemplazarla.
5. Ajustes → Historial → Deshacer permite recuperar cambios mientras no haya modificaciones posteriores en ese archivo.

Las canciones descargadas dentro de la biblioteca de Apple Music o protegidas con DRM no son archivos editables de esta app. Los proveedores de Archivos pueden ser de solo lectura o tener el archivo pendiente de descarga; esos errores se muestran. No se escanea todo el almacenamiento sin el permiso de una carpeta.

## Comprobaciones

Las pruebas C++ originales verificaron preservación de audio y etiquetas con Mutagen en MP3, M4A, FLAC, Ogg, WAV y AIFF. El CI añade lectura/escritura real de letras incrustadas en esos formatos, SYLT, rutas seguras, escaneo de subcarpetas, creación y reemplazo de LRC, protección frente a cambios externos y deshacer. También prueba navegación SwiftUI en iPhone 13.

Consulta `docs/ESTADO.md` para límites y pendientes de prueba física. Los proveedores de iCloud/Archivos y la API de Genius autenticada requieren validación en tu dispositivo y cuenta.

## Alcance de compatibilidad

La app detecta MP3, M4A/MP4, FLAC, Ogg/Vorbis, Opus, WAV, AIFF, APE, WavPack, WMA, DSF/DFF y MPC. Los campos o portadas no admitidos por un formato fallan con un mensaje y se conserva el original. Los seis primeros formatos de la suite tienen verificación nativa local; los demás necesitan muestras y prueba en iOS antes de anunciarlos como comprobados. AAC sin contenedor, archivos DRM y la base interna de Apple Music están fuera del alcance de esta primera versión.

Los renombrados automáticos, análisis de ReplayGain y edición visual de una línea LRC con botón para marcar su tiempo no forman parte de 0.2.0. El editor actual permite cambiar el texto/timestamp directamente y desplazar todos los tiempos.

## Fuentes y créditos

- [Apple · Acceso a carpetas](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Apple · Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [TagLib 2.3.2](https://github.com/taglib/taglib/releases/tag/v2.3.2)
- [utfcpp 4.0.6](https://github.com/nemtrif/utfcpp/tree/v4.0.6)
- [Mapeo de clasificación de contenido](https://docs.mp3tag.de/mapping/#itunesadvisory)
- [LRCLIB](https://lrclib.net/docs)
- [Genius API](https://docs.genius.com/)
- [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API)
- [Cover Art Archive](https://musicbrainz.org/doc/Cover_Art_Archive/API)

Las dependencias y sus licencias se incluyen en `Vendor/`, con SHA-256. No se descargan ni incluyen canciones comerciales. Las muestras pequeñas de prueba proceden de la suite pública de TagLib. El código propio utiliza la licencia MIT.
