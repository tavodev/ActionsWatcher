# ActionsWatcher

[English](README.md)

Una app nativa de macOS para seguir GitHub Actions desde la barra de menús. SwiftUI + AppKit, sin dependencias externas ni servicios intermediarios.

Consulta las ejecuciones, explora sus jobs y pasos, y recibe avisos al terminar sin mantener abierta la web de GitHub.

## Compilar y abrir

La app requiere **macOS 14 o posterior**. Para compilarla, necesitas **Swift 6** y el **SDK de macOS 15 o posterior**, disponibles con Xcode 16 o sus Command Line Tools y en versiones posteriores compatibles con tu Mac. [Requisitos de Xcode](https://developer.apple.com/xcode/system-requirements/)

Desde la raíz del repositorio, compila y abre la app con este comando.

```sh
./scripts/run.sh
```

Para explorar datos ficticios sin conectar GitHub, cierra cualquier instancia abierta de ActionsWatcher y ejecuta el modo demo.

```sh
./scripts/run.sh --demo
```

El script deja la app en `build/ActionsWatcher.app` para que puedas volver a abrirla con un doble clic. Aparece en la barra de menús. El binario se compila para la arquitectura del Mac actual y se firma ad hoc para uso local.

## Conectar GitHub

Puedes usar una sesión existente de GitHub CLI con el botón **Usar mi sesión de GitHub CLI**. La app busca `gh` en las rutas habituales de Homebrew y mantiene su token en memoria durante la sesión. Puedes iniciar sesión con `gh auth login --hostname github.com` o usar un token personal.

Para conectar con un token personal de acceso granular, sigue estos pasos.

1. Abre **Conectar con un token personal → Crear token**.
2. Selecciona un propietario de recursos y los repositorios que quieres monitorear.
3. Asigna acceso de lectura a **Actions**. GitHub incluye acceso de lectura a **Metadata** en estos tokens.
4. Pega el token en la app, pulsa **Conectar** y elige los repositorios que quieras seguir.

Cada token granular se limita a un propietario de recursos. Para repositorios privados de una organización, GitHub puede solicitar autenticación SSO al crear el token y la organización puede exigir su aprobación. La app se conecta a `github.com`. [Tokens personales de GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) · [Autorización SSO](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on)

## Uso diario

1. Selecciona hasta 10 repositorios desde **Repositorios**, en el pie del panel. Puedes buscarlos o añadirlos como `propietario/repositorio` o mediante una URL de GitHub.
2. Consulta las ejecuciones activas y recientes. Usa los filtros o la búsqueda; las celdas del gráfico de actividad también abren su ejecución.
3. Abre una ejecución para ver el anillo de progreso y el mapa de jobs. Las tarjetas muestran su estado y sus pasos terminados; **Ver los N jobs** despliega los restantes.
4. Selecciona una tarjeta para ir al inspector del job. Pulsa un nodo de la línea de pasos para explorar ese paso, o **Seguir actual** para volver al seguimiento del paso actual. **Ver los N pasos** muestra el detalle completo.
5. Ajusta el intervalo, las notificaciones y el inicio con macOS desde **Preferencias**. Usa el botón de actualización del encabezado para solicitar una consulta, respetando la espera vigente si GitHub ha limitado las solicitudes.

El anillo representa jobs terminados sobre jobs publicados por GitHub, incluidos los fallidos, cancelados y omitidos. Las barras representan pasos de cada job. Estos gráficos no estiman el tiempo restante ni representan dependencias entre jobs.

## Qué incluye

- Icono de estado y número de ejecuciones activas en la barra de menús. Clic derecho para abrir o salir.
- Hasta 10 repositorios seleccionados, con búsqueda y adición por nombre o URL. La lista de repositorios tiene paginación.
- Ejecuciones recientes y activas, con workflow, rama, commit, duración e intento. Las ejecuciones activas se consultan también por separado para encontrar builds antiguos que siguen corriendo.
- Filtros de todas, activas y fallidas; búsqueda por repositorio, rama, workflow o título.
- Detalle de la ejecución con un anillo de jobs terminados, un mapa de tarjetas seleccionables y un inspector de pasos. Los jobs fallidos aparecen primero y puedes volver al mapa desde cualquier job.
- Línea interactiva de pasos, con nombres completos disponibles al pasar el cursor y detalle desplegable. Los hashes de acciones se abrevian en pantalla.
- Indicadores animados de actividad, transiciones de progreso y un gráfico de las ejecuciones recientes. Las animaciones respetan **Reducir movimiento** y se pausan al cerrar el panel.
- Cursor de mano sobre tarjetas, filtros, pasos y controles seleccionables. Los campos de entrada mantienen el cursor de texto y los controles deshabilitados no muestran la mano.
- Actualización de los jobs mientras su ejecución está abierta y paginación para matrices grandes.
- Notificaciones de fallos y, opcionalmente, éxitos. Actívalas en **Preferencias → Activar notificaciones en macOS**. Solo se notifican transiciones de activo a terminado observadas durante esta sesión; no se notifican ejecuciones históricas al arrancar. Pulsa una notificación para abrir la ejecución en GitHub.
- Actualización cada 15, 30, 60 o 120 segundos, consultas condicionales con ETag y concurrencia limitada. La app respeta la espera indicada por GitHub, aumenta el intervalo si fallan todos los repositorios y marca como desactualizados los datos afectados.
- Inicio con macOS, configurable desde Preferencias. Para uso permanente mueve la app a Aplicaciones antes de activar esta opción; macOS puede pedir autorizarla en Ítems de inicio.
- Modo de demostración explícitamente identificado, sin acceder a GitHub.

El indicador prioriza ejecuciones activas. Cuando terminan, resume el último resultado conocido de cada combinación de repositorio, workflow y rama en las ejecuciones consultadas; un fallo antiguo de la misma combinación deja de dominar cuando hay una ejecución nueva satisfactoria.

La app sigue los workflows de Actions. Si tu workflow termina antes que un despliegue en otro proveedor, el estado del despliegue externo no está incluido. El detalle muestra jobs y pasos; los logs completos se abren en GitHub.

## Datos y credenciales

ActionsWatcher consulta directamente la API de GitHub mediante solicitudes de lectura y funciona sin analítica. Guarda los tokens ingresados manualmente en Keychain y los tokens obtenidos de GitHub CLI solo en memoria. Las preferencias locales incluyen los repositorios seleccionados, el modo de conexión, el intervalo y las opciones de notificación.

**Desconectar** elimina el token que guarda la app y la selección de repositorios. Tu sesión de GitHub CLI sigue disponible.

## Apariencia

| Uso | Color |
| --- | --- |
| Fondo | `#010736` |
| Tarjetas | `#0D1C42` |
| Superficies elevadas y selección | `#22396F` |
| Texto principal y acentos | `#FCF1D0` |

Los resultados conservan colores semánticos de éxito, espera y fallo, acompañados por iconos y etiquetas. Los controles incluyen nombres de accesibilidad y los textos abreviados ofrecen el nombre completo al pasar el cursor.

## Desarrollo y validación

```sh
./scripts/swift-local.sh test
./scripts/build-app.sh
codesign --verify --strict 'build/ActionsWatcher.app'
```

Las pruebas del núcleo usan respuestas HTTP simuladas. Consulta la guía para conocer la arquitectura, generar capturas PNG de la demo y verificar la app localmente. [Guía de desarrollo](docs/DEVELOPMENT.es.md) · [Historial de cambios](CHANGELOG.es.md)

## Estructura

- `Sources/ActionsWatcherCore`: modelos, cliente HTTP y reglas de seguimiento.
- `Sources/ActionsWatcher`: interfaz, barra de menús, preferencias, Keychain y notificaciones.
- `Tests/ActionsWatcherCoreTests`: pruebas del cliente y comportamiento de monitoreo.
- `scripts`: compilación, empaquetado y generación del icono en código.
- `Resources`: metadatos del bundle de macOS.
- `docs`: notas de desarrollo y validación.

## Licencia

ActionsWatcher se distribuye bajo la licencia MIT. [Texto de la licencia](LICENSE)
