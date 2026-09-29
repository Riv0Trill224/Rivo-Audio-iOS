# RIVØ Audio 0.3.0 — Biblioteca y video

Fecha: 29 de septiembre de 2026. Alcance: iOS y Android.

## Cambios

1. Continuidad del sonido y del tiempo del video al bloquear; la imagen retoma la posición al volver. Asociación audio/video por nombre de archivo sin extensión, exactamente igual, respetando mayúsculas y acentos. Los duplicados se eligen manualmente.
2. Ajustes → Escanear biblioteca completa. Revisa carpetas autorizadas y archivos locales; conserva playlists, puntuaciones, carátulas y datos editados. Informa fuentes no accesibles.
3. Transferir se llama Ajustes, con las funciones de importación y transferencia existentes.
4. Inicio: Artistas, Álbumes, Géneros, Tracks, Playlists y Mejores Puntuados. Playlists persistentes con creación, nombre, selección de pistas, orden y eliminación.
5. Video con pantalla completa y rotación, sin crear otro reproductor ni reiniciar la posición.
6. Letras LRC sobre video y control Mostrar/Ocultar; preferencia persistente. Las letras sin tiempos se muestran como texto.
7. Fichas de artistas consultables en MusicBrainz, guardadas para lectura sin conexión. Se exige identidad única; una coincidencia ambigua no se asigna automáticamente.
8. Créditos editables por canción y búsqueda de grabación en MusicBrainz: intérpretes, productor, ingeniería, mezcla, masterización, composición, letra, instrumentos y año cuando existan. El usuario selecciona la versión; se conserva la fuente y se combinan los créditos sin borrar los manuales.
9. El video conserva la cola y avanza al siguiente elemento al terminar. No repite la última pista automáticamente. Repetir una pista sigue siendo una elección explícita.
10. Playlists de video con el mismo ciclo de edición y persistencia.
11. Nombre de la salida de audio junto al formato del archivo. iOS consulta la ruta de AVAudioSession y ofrece símbolos del sistema para auriculares/Beats/AirPods; Android consulta la ruta multimedia del sistema. El nombre procede del sistema, no se fija “Beats Solo Buds”.

## Alcance y límites

- Las funciones son comunes a las dos plataformas; los controles conservan la interfaz nativa de cada una.
- MusicBrainz no garantiza créditos completos ni biografías extensas. La función permite completar datos manualmente; nunca inventa participantes. Sus consultas son explícitas y se espacian; no se consulta cada vez que se dibuja una pantalla.
- El logo de todas las marcas no puede identificarse a partir de un nombre Bluetooth renombrable. Se conserva el nombre real que expone el sistema y un símbolo de dispositivo donde está disponible. No se presenta una marca deducida como identidad certificada.
- En Android, las importaciones antiguas que no conservaron su nombre original necesitan volver a escanear su carpeta/reimportarse, o completar “Nombre exacto del archivo original” en Editar biblioteca, para asociar audio y video con seguridad.
- Las carpetas revocadas o desconectadas no pueden releerse hasta recuperar acceso. Las copias locales siguen disponibles.
- Bloqueo, batería y nombre específico de Beats Solo Buds en iPhone físico requieren prueba con el equipo del usuario. Los simuladores/emuladores no sustituyen esa comprobación.
- iOS se entrega como IPA sin firma para firmar con el método de instalación habitual. Android es una APK de pruebas, no una publicación en tienda.

## Validación incluida en los repositorios

- iOS: pruebas de coincidencia exacta y ambigüedad, persistencia tras escaneo, créditos de grabación y obra, avance de cola, cambio audio/video conservando posición; controles y límites de pantalla de iPhone 13.
- Android: pruebas instrumentadas de persistencia, escaneo, créditos y asociación; pantalla completa, letras ocultables, rotación, bloqueo y avance al siguiente elemento; reproducción, forma de onda, letras y ecualización existentes.
- Consultar el resultado del workflow del commit entregado para el estado de ejecución; la presencia de una prueba no implica que haya pasado.

## Referencias técnicas

- https://developer.apple.com/documentation/avfoundation/avplayer/audiovisualbackgroundplaybackpolicy
- https://developer.android.com/reference/android/media/AudioManager#getAudioDevicesForAttributes(android.media.AudioAttributes)
- https://musicbrainz.org/doc/MusicBrainz_API
- https://musicbrainz.org/relationships/artist-recording
