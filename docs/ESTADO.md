# Estado del desarrollo · 25 de septiembre de 2026

El proyecto iOS ya está cargado en este repositorio. La versión inicial compiló para simulador y dispositivo y produjo una IPA sin firma mediante GitHub Actions.

## Cambios posteriores a la entrega del ZIP

- El EQ conserva bandas, ganancias, estado activo y preset entre sesiones.
- Los presets se interpolan para que los modos de 15 y 31 bandas tengan una curva consistente.
- El historial suma tiempo de reproducción en lugar de usar la posición de la canción. Adelantar no cuenta como tiempo escuchado.
- Buscar una posición conserva el estado de pausa y evita reiniciar el registro de escucha.
- El motor limpia su estado ante un error y reconecta el formato de audio al cambiar de archivo.
- Abrir un video pausa el audio; el reproductor de video conserva su instancia mientras la vista está abierta.
- Se añadió una prueba de interfaz que inicia la app y abre Biblioteca, Ecualizador y Transferir.

## Pendientes antes de declarar la app lista para uso diario

- Prueba física de audio, formatos, EQ, bloqueo de pantalla e interrupciones.
- Transferencias reales desde iCloud Drive, PC y FTP.
- Manejo completo de errores y cancelación de transferencias FTP.
- Presets personales con nombre y editor de carátulas con guardado/cancelación coherentes.
- Artistas múltiples y mejoras de coincidencias de letras.
- Validación con una cuenta real de Last.fm: la conexión ya está implementada en v0.1.1; falta introducir las credenciales y autorizar la cuenta.
- Fuente externa de rankings: actualmente hay estrellas personales y un campo manual.
- Metadatos embebidos: actualmente se edita el catálogo de la app, no el archivo musical.

La IPA de Actions no está firmada. Necesita firma e instalación con el método personal elegido. No se ha probado todavía en el iPhone del usuario.

## Verificación completada

La ejecución [36207444049](https://github.com/Riv0Trill224/Rivo-Audio-iOS/actions/runs/36207444049) terminó correctamente para el código `50cb98d83d700ccb70b77e8586a342eecb14096f`:

- Compilación para simulador: correcta.
- Prueba de arranque y navegación: 1 prueba, 0 fallos.
- Compilación para dispositivo: correcta.
- IPA sin firma: generada como artefacto `RivoAudio-iOS-v0.1.0-unsigned`.

Esta prueba no reproduce un archivo de audio ni valida una transferencia: ambas comprobaciones siguen pendientes en el dispositivo.


## v0.1.1 · Fotos automáticas, Last.fm y Audio/Video

- **Fotos:** búsqueda de identidad exacta en MusicBrainz, relación Wikidata y fotografía de Wikimedia Commons. La app conserva imagen, autor, licencia y enlace de procedencia. Se busca al mostrar el artista; si no existe una identidad única o una foto con licencia identificada, se informa en el perfil. Hay actualización manual de la búsqueda automática.
- **Last.fm:** configuración de API key y shared secret en la app, autorización en el navegador y sesión en Keychain. Incluye Now Playing, scrobbles por tiempo escuchado, cola persistente, reconexión y visualización de rechazos. No se suben credenciales al repositorio. Los títulos/artistas derivados de nombres de archivo requieren confirmación en el editor antes de enviarse.
- **Audio/Video:** busca archivos complementarios en la biblioteca. Usa título normalizado, artista, duración, nombre de archivo y similitud de escritura. Distingue versiones live/remix/acoustic. Un único par de alta confianza habilita el cambio directo; los casos dudosos muestran candidatos.
- El cambio conserva el segundo de reproducción y el estado de pausa. Conserva el registro de escucha de la canción para no duplicarlo al cambiar de fuente. Una introducción distinta en el videoclip puede requerir ajustar la posición manualmente.
- El video usa AVPlayer; el EQ de AVAudioEngine se aplica al modo Audio. No se descargan videos de servicios externos.

### Pruebas añadidas

Firma y codificación de solicitudes de Last.fm; interpretación de aceptados/rechazados; coincidencias correctas, ambiguas y con errores de escritura; atribución de fotos e identidad ambigua con respuestas simuladas; cambio real entre un WAV y un MOV generados para la prueba, conservando posición y pausa; navegación hasta la configuración de Last.fm.

Las pruebas de Last.fm y fotos usan datos de prueba. No demuestran una autorización ni envío real de scrobbles con la cuenta del usuario, ni disponibilidad de una foto para cada artista.

### Resultado de validación v0.1.1

La ejecución [36210104860](https://github.com/Riv0Trill224/Rivo-Audio-iOS/actions/runs/36210104860) terminó en verde para `7593405192b4edfbb3b7c6535b081b4503f5e556`: 7 pruebas de integración/lógica y 1 prueba de interfaz, todas sin fallos. Compiló para simulador y dispositivo y generó `RivoAudio-iOS-v0.1.1-unsigned`. La autorización de Last.fm con credenciales reales y las pruebas físicas en el iPhone siguen pendientes.

## v0.1.2 · Corrección de instalación con SideStore

El primer intento físico rechazó el parámetro `appIdName` con valor `RIVØ Audio`. Se cambia `CFBundleDisplayName` a `Rivo Audio` (ASCII), versión 0.1.2, build 3. La identidad visual dentro de la app conserva RIVØ. Pendiente confirmar la instalación en el iPhone con esta IPA.

## v0.1.3 · Lectura de audio y nueva interfaz

- La v0.1.2 ya se instaló y abrió en el iPhone. Se reportó un error Core Audio 2003334207 al reproducir Acid Drip. No se recibió el archivo original; este código es genérico y no confirma por sí solo la causa.
- Importación coordinada con proveedores de Archivos/iCloud, copia temporal y validación de archivo no vacío. Rutas relativas por componentes canónicos para evitar discrepancias de enlaces simbólicos.
- Si AVAudioFile no abre el archivo, se intenta decodificar su pista con AVAssetReader a PCM temporal, manteniendo el motor con EQ. No modifica el original. Errores explicativos para archivos vacíos, inaccesibles, protegidos o incompatibles.
- Reproductor oscuro con carátula amplia, fondo difuminado, controles circulares, acceso a EQ/letras/cola y forma de onda muestreada del audio. La biblioteca abre directamente el reproductor; menú contextual para editar. EQ con controles verticales y presets rápidos.
- Pruebas nuevas: importación de nombres Unicode y caracteres reservados, rutas con enlaces simbólicos, AAC a PCM y reproducción con EQ, archivos vacíos/ausentes e interfaz del reproductor.
- Pendiente reproducir el archivo original en el teléfono. El respaldo no añade códecs que iOS no soporte.
