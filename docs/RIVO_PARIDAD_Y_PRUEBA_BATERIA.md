# Rivo Audio · estabilización iOS y paridad Android

## Build iOS 0.1.6

Esta entrega reduce trabajo de la app durante la reproducción. El motor de audio sigue manejando el sonido; el temporizador del reproductor solo actualiza progreso y scrobbling. Ahora se detiene al pausar, corre cada 0,5 s con la app visible y cada 10 s en segundo plano. Now Playing se publica al cambiar de estado y con menor frecuencia cuando la interfaz está visible. La lista de artistas ya no inicia consultas de red por cada fila; la foto se solicita al abrir el perfil. Las consultas fallidas de fotos conservan su espera de 24 horas entre aperturas. Las carátulas se decodifican como miniaturas de hasta 900 px y se reutilizan con un límite de caché de 24 MiB. El catálogo guardado se carga sin escanear todos los archivos al arrancar; Importar y Actualizar siguen escaneando.

### Prueba física prioritaria

1. Instalar la IPA 0.1.6, abrirla y comprobar que la biblioteca anterior aparece y que una canción local se reproduce.
2. Cargar el teléfono, anotar porcentaje, salud de batería, hora y si se utiliza Bluetooth o altavoz. Desactivar FTP y dejar la misma red y volumen en ambas pruebas.
3. Reproducir una lista local durante 60 minutos con pantalla bloqueada. Anotar porcentaje final, minutos de actividad en segundo plano y si hubo saltos o interrupciones. No interpretar el porcentaje de actividad de Ajustes como puntos de batería gastados.
4. Repetir solo si el resultado es razonable. Si sigue elevado, guardar capturas de Batería y una traza Energy Log de Instruments cuando haya Mac disponible. El descenso anterior de 50 % a 18 % en una hora es el punto de comparación, no una causa demostrada.

La compilación y las pruebas de simulador no miden consumo real. La batería del iPhone 13 tiene desgaste conocido, así que la comparación debe hacerse en el mismo equipo y condiciones parecidas.

## Pendientes de iOS

- Diagnosticar con Energy Log si el gasto sigue alto, en particular AVAudioEngine/EQ, lectura de archivos y trabajo de red.
- Administrador de letras descargadas: ubicación persistente `Documents/Lyrics/`, asociación estable por identificador de canción, migración desde el campo `lyrics` de `library.json`, edición, reemplazo y eliminación. No asumir que las letras actuales ya están en esa carpeta: hoy se guardan en el catálogo o en un `.lrc` junto al audio.
- Automatización de búsqueda de letras solo al necesitarla, con selección manual ante coincidencias ambiguas y sin reintentos en bucle. Hoy la búsqueda se inicia manualmente desde la vista de letras.
- Revisar fotografías de artistas con casos reales donde la fuente no encuentra imagen; mantener atribución de Wikimedia Commons.
- Medir fluidez en Artistas con una biblioteca grande; reducir cálculos repetidos por fila si persiste el lag.

## Contrato funcional Android

Android debe reproducir la misma navegación, biblioteca local por carpetas, cola, historial, letras sincronizadas, carátulas y fotos de artistas, EQ, Last.fm y selector de audio/vídeo que se validen en iOS. Compartir nombres visibles y reglas de coincidencia; implementar permisos, reproducción en segundo plano, notificación multimedia, caché y persistencia con las APIs propias de Android. La detección RG DS y la salida USB-C/OTG para DAC son capacidades específicas de Android. No prometer salida bit perfect hasta medir ruta de audio y mezcla del dispositivo.

Prioridad: estabilizar reproducción y batería en iOS, fijar comportamiento de letras y biblioteca, y luego usar ese comportamiento probado como lista de aceptación para Android `com.riv0trill.rivoaudio`.
