# Estado de desarrollo · 2026-10-07

Objetivo: app nativa iOS llamada Rivo Metadata Editor, salida IPA, paleta exacta de Rivo Audio iOS y referencia principal iPhone 13. Package: `com.riv0trill.rivometadataeditor`.

Estado verificable: código escrito, núcleo TagLib compilado en Linux y pruebas independientes de seis formatos superadas. No existe IPA ni compilación SwiftUI/simulador en este entorno. No se creó un repositorio remoto ni se modificó Rivo Audio iOS.

## Arquitectura

- `Bridge/TagCore.*`: núcleo C++ portable. FileRef/PropertyMap conserva etiquetas ajenas al parche. `rtng` se escribe como byte MP4; los otros contenedores usan ITUNESADVISORY. PICTURE conserva otras imágenes y reemplaza la portada frontal/primera en MP4.
- `Bridge/RMEBridge.*`: puente Objective-C++ a Swift; errores explícitos, cadenas UTF-8 y portada binaria.
- `App/FileService.swift`: actor serial. Bookmarks de carpetas, NSFileCoordinator, escaneo recursivo, originales fuera del sandbox, staging vecino, verificación, respaldos internos, hashes SHA-256 y deshacer protegido ante cambios posteriores.
- `App/Services.swift`: actor de red. LRCLIB, MusicBrainz, Cover Art Archive, límite por host, caché TTL de siete días y reintentos. Las consultas envían título/artista/álbum/duración; no envían audio.
- `App/Core.swift`: modelos, clasificación, motor conservador de coincidencias, nombres sidecar y manipulación/validación LRC.
- `App/Store.swift`: biblioteca y cola persistente, estados publicados en MainActor, tareas cancelables, selección, progreso, ETA, lote de letras/metadatos y modo solo analizar.
- `App/App.swift`, `Editor.swift`, `LyricsEditor.swift`: navegación, editor individual/múltiple, búsqueda y vista previa, portadas, texto LRC, reproducción y ajustes/historial.
- `scripts/`: construye biblioteca estática XCFramework para dispositivo y simulador; genera Xcode con XcodeGen; compila app y empaqueta Payload/*.app como IPA sin firma.

## Identidad visual

Valores obtenidos de `Riv0Trill224/Rivo-Audio-iOS/RivoAudio/PlayerStyle.swift`, rama main:

| Uso | RGB normalizado |
|---|---|
| Acento | 0.83 / 0.68 / 1.00 |
| Fondo | 0.035 / 0.045 / 0.080 |
| Superficie | 0.100 / 0.105 / 0.160 |

Liquid Glass se aplica con `glassEffect` en iOS 26+. Componentes nativos, tema oscuro y tamaño adaptable. No se ha renderizado la app en un simulador real.

## Primer bloqueo para la IPA

Falta un repositorio independiente `Riv0Trill224/Rivo-Metadata-Editor-iOS` o un Mac con Xcode. La conexión GitHub consultada permite leer los cuatro repositorios existentes pero no expone una acción para crear un repositorio nuevo. No se reutilizó un repositorio de otro proyecto como destino de escritura.

Próximo paso: subir este proyecto a un repositorio nuevo; GitHub Actions iniciará automáticamente la compilación y pruebas. Si el CI revela errores de Swift/Xcode, corregir antes de marcar el build como funcional. La IPA no firmada se instala mediante la firma personal de SideStore.

## Pruebas de aceptación pendientes en iOS

1. Elegir carpeta local y de iCloud; reiniciar app y restaurar permisos.
2. Editar MP3/M4A/FLAC reales; confirmar tags y portada en un editor independiente.
3. Comprobar explícito y limpio en cada reproductor que utilice el usuario; Apple Music puede requerir actualizar su propia base al importar.
4. Ejecutar un lote de al menos 100 canciones; verificar sidecars, ETA, cancelación y no sobrescritura de LRC existentes.
5. Probar error de red, proveedor de solo lectura, archivo no descargado y falta de espacio.
6. Comprobar cola manual, selección de versión, texto LRC y ajuste temporal.
7. Deshacer cambios; comprobar detección de cambios externos.
8. Revisar pantalla iPhone 13, accesibilidad, scroll y memoria/batería.

La escritura final depende de que el proveedor admita sustituir un archivo. Un error conserva el backup y se comunica; no se usa como fallback un borrado directo del original. Los respaldos se conservan hasta deshacer y pueden ocupar espacio; añadir gestión explícita del tamaño en una revisión posterior. El historial persistido antes de la sustitución también puede incluir una operación que no llegó a finalizar; en ese caso Deshacer la rechaza porque el hash final no coincide, y el backup sigue disponible internamente.
