# RIVØ Audio para iOS

Reproductor de música personal para iPhone. La primera versión está diseñada para reproducir archivos propios sin cuenta ni servidor. Su EQ de 10 bandas forma parte del motor de reproducción.

## Lo que hace v0.4.0

- Vincula carpetas, música y videos desde **Archivos**, incluida iCloud Drive, y reproduce los originales sin duplicar la biblioteca. Conserva permisos mediante marcadores de acceso.
- Detecta archivos añadidos a `Documents/Music`, muestra canciones y artistas, permite buscar y reproduce audio en segundo plano.
- EQ de 10, 15 o 31 bandas con controles de ±12 dB, activación y presets. Los ajustes se conservan al cerrar la app y los presets se adaptan a los tres modos.
- Permite editar título, artista, álbum, carátula y valoración de 1 a 5 estrellas **dentro de la biblioteca**. Conserva intactos los archivos originales.
- Abre un perfil por artista con sus canciones locales y descarga automáticamente su foto desde Wikimedia Commons, identificándolo con MusicBrainz/Wikidata. Conserva la imagen y sus créditos para uso sin conexión. Si la identidad es ambigua o no hay foto, lo informa.
- Muestra controles de reproducción y carátula en pantalla bloqueada y Centro de Control.
- Lee `.lrc` junto al archivo, y permite buscar letras sincronizadas mediante LRCLIB. Si el título no coincide, ofrece candidatos para elegir manualmente; no asigna letras dudosas automáticamente.
- Inicio muestra los últimos reproducidos por fecha y hora. La pestaña Biblioteca abre álbumes en cuadrícula, artistas, géneros, tracks, playlists y favoritos.
- Cada álbum muestra carátula, artista, género/año disponibles, duración y pistas ordenadas por disco y número.
- Reproduce videos locales e incluye un switch Audio/Video cuando detecta un par. Exige el mismo nombre base de archivo (sin extensión), incluidas mayúsculas y acentos; pide elegir si hay duplicados y conserva el segundo de reproducción y el estado de pausa. El EQ se aplica al motor de audio, no al sonido del video.
- Comparte `Documents` con Finder / Apple Devices / iTunes para PC, y recibe archivos por FTP pasivo desde la misma Wi-Fi mientras la app está abierta.

## Límites de esta entrega

- El campo «Dato de lista» acepta una referencia a Billboard u otra lista **ingresada por el usuario**. No se consulta ni se infiere automáticamente un ranking sin una fuente autorizada.
- Last.fm envía Now Playing y scrobbles después de configurar tu API key y shared secret y autorizar tu cuenta en el navegador. Las credenciales se guardan en Keychain. Las escuchas pendientes se conservan para reintentar; los rechazos se muestran. Las canciones identificadas solo por nombre de archivo requieren confirmar título/artista en el editor antes de enviarlas.
- iCloud Drive se usa mediante el selector **Archivos**: vincular conserva su ubicación original. Los archivos deben estar descargados para escucharlos sin conexión. No se accede a pistas protegidas de Apple Music.
- Los formatos admitidos por importación incluyen MP3, AAC/M4A, ALAC, WAV, AIFF, CAF, FLAC y MP4/M4V/MOV. Su reproducción concreta depende de los decodificadores de iOS; verificar FLAC en el dispositivo antes de afirmar compatibilidad completa.
- El servidor FTP solo atiende mientras RIVØ Audio está abierta y activa. Usa una clave temporal, pero FTP no cifra tráfico: usar únicamente una red local confiable.
- Editar metadatos y carátulas modifica el catálogo de RIVØ Audio, no las etiquetas embebidas en MP3/M4A/FLAC. La foto del artista se obtiene automáticamente de las fuentes indicadas.

## Copiar música desde una PC

En **Apple Devices o iTunes para Windows**, abre la sección Archivos compartidos de RIVØ Audio y añade una carpeta `Music` en Documentos, con la música dentro. En macOS, usa Finder. Luego abre la app y usa Escanear biblioteca completa en Ajustes. También puedes importarla desde Archivos en el iPhone.

Para FTP: en la pestaña **Ajustes**, activa el servidor. En un cliente FTP de la misma Wi-Fi usa la dirección indicada, puerto `2121`, usuario `rivo`, clave temporal mostrada y modo pasivo. Sube archivos de audio/video a `/`.

## Compilar

El proyecto se describe en `project.yml`. En macOS con Xcode y XcodeGen:

```sh
xcodegen generate
xcodebuild -project RivoAudio.xcodeproj -scheme RivoAudio -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

El workflow en `.github/workflows/build-ios.yml` compila para simulador y dispositivo, y empaqueta una **IPA sin firma** como artefacto. Extrae el ZIP directamente en la raíz de un repositorio GitHub nuevo para que Actions lo detecte.

La IPA necesita que SideStore la firme con tu Apple Account antes de instalarla. No subas credenciales Apple ni archivos de emparejamiento al repositorio. La firma gratuita requiere renovación periódica.

## Privacidad

La biblioteca, puntuaciones, fotos, letras e historial se guardan en el dispositivo. La búsqueda de letras consulta LRCLIB cuando la activas. Al mostrar artistas sin foto se consulta MusicBrainz, Wikidata y Wikimedia Commons. Last.fm solo recibe escuchas después de conectar la cuenta y habilitar el envío. El FTP permanece apagado hasta que lo enciendes.

## Versión

`0.4.0` (build 10) · identificador `com.riv0trill.rivoaudio.ios` · iOS 17 o posterior.

Consulta [el estado del desarrollo](docs/ESTADO.md) para conocer las validaciones y funciones pendientes.

## Configurar Last.fm

1. En **Ajustes → Last.fm y escuchas**, introduce la API key y el shared secret de tu cuenta API de Last.fm y pulsa Guardar.
2. Pulsa **Autorizar en Last.fm** y acepta el acceso en su página.
3. Regresa a RIVØ y pulsa **Ya autoricé · conectar cuenta**.
4. Deja activo **Enviar escuchas**. La cola muestra pendientes y rechazos; puedes reintentar manualmente.

El cambio Audio/Video conserva el tiempo absoluto: si el videoclip tiene una introducción distinta, ajusta la posición. No descarga videos de Spotify ni de otros servicios; busca los archivos importados en tu biblioteca.

## Migrar la biblioteca anterior

En **Ajustes → Vincular originales y liberar copias verificadas**, la app recupera las carpetas seleccionadas anteriormente y verifica tamaño y SHA-256 antes de eliminar una copia interna idéntica. Mantiene IDs, puntuaciones, metadatos editados y playlists. Si no hay acceso o los archivos difieren, conserva la copia. Los originales nunca se eliminan. Si cambió la ubicación, utiliza **Volver a vincular carpeta**. Los archivos antiguos importados individualmente sin una fuente registrada no se limpian automáticamente.

## Video, consumo y tamaño

Pantalla completa admite los dos sentidos horizontales y restaura vertical al cerrar. El motor de audio se pausa junto con la reproducción; los efectos neutros se omiten, el reloj visual no actualiza la biblioteca en segundo plano y las miniaturas se almacenan en caché. FTP se apaga al pasar a segundo plano. La conversión de compatibilidad utiliza archivos temporales limitados a 64 MB; los formatos nativos se leen directamente.

Actions comprueba que el paquete de aplicación descomprimido no supere 100 MB. La música del usuario, miniaturas y datos de uso son almacenamiento separado. Las pruebas de simulador verifican comportamiento; el consumo real debe medirse en un iPhone físico a igual tiempo, volumen y salida.
