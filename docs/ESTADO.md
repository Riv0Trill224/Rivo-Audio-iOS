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
- Conexión real a Last.fm: actualmente solo existe historial local.
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
