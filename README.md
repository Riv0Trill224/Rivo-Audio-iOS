# RIVØ Audio para iOS

Reproductor de música personal para iPhone. La primera versión está diseñada para reproducir archivos propios sin cuenta ni servidor. Su EQ de 10 bandas forma parte del motor de reproducción.

## Lo que hace v0.1.0

- Importa música o videos desde **Archivos**, incluida iCloud Drive, y los copia a la biblioteca de la app.
- Detecta archivos añadidos a `Documents/Music`, muestra canciones y artistas, permite buscar y reproduce audio en segundo plano.
- EQ de 10, 15 o 31 bandas con controles de ±12 dB, activación y presets. Los ajustes se conservan al cerrar la app y los presets se adaptan a los tres modos.
- Permite editar título, artista, álbum, carátula y valoración de 1 a 5 estrellas **dentro de la biblioteca**. Conserva intactos los archivos originales.
- Abre un perfil por artista con todas sus canciones locales y foto elegida por el usuario.
- Muestra controles de reproducción y carátula en pantalla bloqueada y Centro de Control.
- Lee `.lrc` junto al archivo, y permite buscar letras sincronizadas mediante LRCLIB. Si el título no coincide, ofrece candidatos para elegir manualmente; no asigna letras dudosas automáticamente.
- Lleva un historial local después de escuchar la mitad o 4 minutos de una canción de más de 30 segundos; adelantar no cuenta como tiempo escuchado.
- Reproduce videos importados en la pestaña de detalles.
- Comparte `Documents` con Finder / Apple Devices / iTunes para PC, y recibe archivos por FTP pasivo desde la misma Wi-Fi mientras la app está abierta.

## Límites de esta entrega

- El campo «Dato de lista» acepta una referencia a Billboard u otra lista **ingresada por el usuario**. No se consulta ni se infiere automáticamente un ranking sin una fuente autorizada.
- La sección de scrobbling conserva escuchas en el iPhone. La conexión con Last.fm necesita una API key, autorización de la cuenta y un manejo seguro de la sesión; aún no envía reproducciones a Last.fm.
- iCloud Drive se usa mediante el selector **Archivos**: importar copia el archivo al almacenamiento local para reproducción sin conexión. No se accede a pistas protegidas de Apple Music.
- Los formatos admitidos por importación incluyen MP3, AAC/M4A, ALAC, WAV, AIFF, CAF, FLAC y MP4/M4V/MOV. Su reproducción concreta depende de los decodificadores de iOS; verificar FLAC en el dispositivo antes de afirmar compatibilidad completa.
- El servidor FTP solo atiende mientras RIVØ Audio está abierta y activa. Usa una clave temporal, pero FTP no cifra tráfico: usar únicamente una red local confiable.
- Editar metadatos y carátulas modifica el catálogo de RIVØ Audio, no las etiquetas embebidas en MP3/M4A/FLAC. La foto del artista es seleccionada localmente.

## Copiar música desde una PC

En **Apple Devices o iTunes para Windows**, abre la sección Archivos compartidos de RIVØ Audio y añade una carpeta `Music` en Documentos, con la música dentro. En macOS, usa Finder. Luego abre la app y toca actualizar en Biblioteca. También puedes importarla desde Archivos en el iPhone.

Para FTP: en la pestaña **Transferir**, activa el servidor. En un cliente FTP de la misma Wi-Fi usa la dirección indicada, puerto `2121`, usuario `rivo`, clave temporal mostrada y modo pasivo. Sube archivos de audio/video a `/`.

## Compilar

El proyecto se describe en `project.yml`. En macOS con Xcode y XcodeGen:

```sh
xcodegen generate
xcodebuild -project RivoAudio.xcodeproj -scheme RivoAudio -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

El workflow en `.github/workflows/build-ios.yml` compila para simulador y dispositivo, y empaqueta una **IPA sin firma** como artefacto. Extrae el ZIP directamente en la raíz de un repositorio GitHub nuevo para que Actions lo detecte.

La IPA necesita que SideStore la firme con tu Apple Account antes de instalarla. No subas credenciales Apple ni archivos de emparejamiento al repositorio. La firma gratuita requiere renovación periódica.

## Privacidad

La biblioteca, puntuaciones, fotos, letras e historial se guardan en el dispositivo. Solo la búsqueda de letras hace una solicitud a LRCLIB cuando la activas. El FTP permanece apagado hasta que lo enciendes.

## Versión

`0.1.0` · identificador `com.riv0trill.rivoaudio.ios` · iOS 17 o posterior.

Consulta [el estado del desarrollo](docs/ESTADO.md) para conocer las validaciones y funciones pendientes.
