# Desarrollo de ActionsWatcher

[English](DEVELOPMENT.md)

Swift Package Manager organiza el proyecto en tres targets, `ActionsWatcher`, `ActionsWatcherCore` y `ActionsWatcherCoreTests`. Usa los frameworks del SDK de macOS.

## Compilar y ejecutar

Instala las herramientas indicadas en el README y ejecuta estos comandos desde la raíz del repositorio. [Requisitos de compilación](../README.es.md#compilar-y-abrir)

```sh
./scripts/build-app.sh
open build/ActionsWatcher.app
```

`build-app.sh` compila en modo release, crea el bundle, genera el icono desde código y aplica la firma. `CONFIGURATION=debug ./scripts/build-app.sh` genera un bundle de depuración. Para trabajar desde Xcode, abre `Package.swift`. Para generar el bundle `.app`, usa el script.

`scripts/swift-local.sh` mantiene las cachés y la configuración de SwiftPM en `.build/`. Desactiva el sandbox adicional de SwiftPM para permitir ejecutar el compilador en entornos que ya imponen su propio sandbox. No configura el sandbox de la app.

Los directorios `.build/`, `.swiftpm/`, `build/` y `artifacts/` se excluyen de Git. El empaquetado usa la arquitectura del Mac que compila y firma ad hoc por defecto. La variable `SIGN_IDENTITY` permite elegir otra identidad para la firma. La distribución de un binario con Developer ID requiere configurar Hardened Runtime, un sello de tiempo seguro y la notarización según la guía de Apple. [Notarización de software para macOS](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Incluye el aviso de copyright y el texto de la licencia cuando distribuyas copias del proyecto. [Licencia MIT](../LICENSE)

## Arquitectura

| Componente | Responsabilidad |
| --- | --- |
| `ActionsWatcherApp.swift` | Ciclo de vida, `NSStatusItem`, popover, notificaciones y renders nativos. |
| `MonitorStore.swift` | Estado de la interfaz, sesión, repositorios, consultas periódicas y avisos de finalización. |
| `Credentials.swift` | Lectura de la sesión de GitHub CLI y almacenamiento de tokens personales en Keychain. |
| `GitHubClient.swift` | Consultas GET a GitHub, caché ETag en memoria, paginación y límites de solicitudes. |
| `Models.swift` | Estados, validación de repositorios, ordenación y seguimiento de transiciones de finalización. |
| `WorkflowProgress.swift` | Conteo de progreso, prioridad de jobs y abreviación de hashes para la interfaz. |
| `ProgressVisuals.swift` | Anillo, tarjetas de jobs, barras de pasos e indicadores de actividad. |
| `RunDetailView.swift` | Mapa de jobs e inspector interactivo de pasos. |
| `HandCursor.swift` | Cursor de mano para controles habilitados, con compatibilidad para macOS 14. |
| `Theme.swift` | Paleta, estilos compartidos y presentación de estados. |

El cliente HTTP es un actor y el estado de la interfaz está aislado al actor principal. Se consultan hasta tres repositorios a la vez. Cada repositorio aporta sus 20 ejecuciones recientes y las ejecuciones activas; las activas se consultan con paginación. Si una ejecución antes activa desaparece de esas listas, se consulta por ID para recuperar su resultado final.

Los jobs se consultan por intento, con paginación, cuando se abre una ejecución y cuando esa ejecución se actualiza. El mapa agrupa estados y prioriza fallos, actividad y espera; no infiere un grafo de dependencias.

Las animaciones de actividad usan `TimelineView`. La visibilidad del popover controla su pausa, y la preferencia **Reducir movimiento** desactiva el movimiento continuo y las transiciones. El cursor utiliza `pointerStyle` en macOS 15 o posterior y rectángulos de cursor de AppKit en macOS 14.

## Datos y compatibilidad del nombre

El nombre de producto, ejecutable y paquete es **ActionsWatcher**. Se conserva el identificador interno `dev.tavodev.actions-bar` en `Info.plist` y en el servicio de Keychain para mantener el acceso a preferencias y credenciales de la app anterior. Cambiar estos identificadores requiere planificar una migración de datos.

Las preferencias guardan repositorios seleccionados, modo de conexión, intervalo y opciones de notificación. Los tokens personales se almacenan en Keychain; los obtenidos de GitHub CLI y la caché de respuestas se conservan en memoria. Desconectar no cierra la sesión de `gh`.

## Validación

```sh
./scripts/swift-local.sh test
./scripts/build-app.sh
codesign --verify --strict build/ActionsWatcher.app
plutil -lint build/ActionsWatcher.app/Contents/Info.plist
git diff --check
```

Las pruebas usan respuestas HTTP simuladas y verifican las reglas de progreso, estados y ordenación, el seguimiento de finalizaciones, los reintentos, la paginación y los límites de solicitudes. La lista de comprobaciones manuales al final de esta sección cubre la interfaz y la conexión con una cuenta real.

Con el bundle compilado y una sesión gráfica de macOS activa, puedes generar capturas con datos ficticios sin conectar GitHub.

```sh
build/ActionsWatcher.app/Contents/MacOS/ActionsWatcher --preview artifacts/previews
```

Revisa `dashboard.png`, `detail.png`, `job-inspector.png`, `detail-failure.png`, `detail-waiting.png`, `repositories.png`, `settings.png` y `onboarding.png`. El render usa AppKit para incluir los controles nativos. Requiere acceso a los servicios gráficos de macOS; un sandbox puede bloquear ese acceso aunque la compilación funcione.

El mismo comando genera tres pares de imágenes del indicador de actividad. Puedes comparar los pares con Python 3.

```sh
python3 - <<'PY'
from pathlib import Path

for name, expected_equal in [
    ("motion", False),
    ("reduced-motion", True),
    ("paused-motion", True),
]:
    first = Path(f"artifacts/previews/{name}-1.png").read_bytes()
    second = Path(f"artifacts/previews/{name}-2.png").read_bytes()
    assert (first == second) == expected_equal, name
    print(f"{name}: OK")
PY
```

Esta comparación comprueba el movimiento del indicador y sus estados de pausa; no sustituye una revisión del resto de las transiciones o una prueba de clics y navegación.

Para una revisión manual, conecta GitHub, selecciona repositorios, abre una ejecución, cambia de job y paso, verifica el cursor sobre los controles y comprueba una notificación de finalización. Revisa también el comportamiento con **Reducir movimiento** activado.
