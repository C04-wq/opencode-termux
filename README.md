<p align="center">
  <a href="https://opencode.ai">
    <img src="opencode-logo.svg" alt="OpenCode" width="64" height="80">
  </a>
</p>

<h1 align="center">opencode-termux</h1>

<p align="center">
  <a href="https://www.npmjs.com/package/opencode-termux"><img src="https://img.shields.io/npm/v/opencode-termux?style=for-the-badge" alt="npm"></a>
  <img src="https://img.shields.io/badge/Platform-Termux-green?style=for-the-badge" alt="Termux">
  <img src="https://img.shields.io/badge/Architecture-aarch64-blue?style=for-the-badge" alt="aarch64">
  <a href="https://github.com/C04-wq/opencode-termux/actions/workflows/auto-update.yml"><img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/auto-update.yml?style=for-the-badge&label=release" alt="Estado del workflow"></a>
</p>

<p align="center">
  <b>OpenCode para Termux en Android ARM64, empaquetado y actualizado automáticamente.</b>
</p>

`opencode-termux` utiliza el binario ARM64 musl publicado por OpenCode y lo empaqueta con el runtime necesario para Termux. No requiere root.

## Instalación

En Termux aarch64:

```bash
npm install -g opencode-termux
opencode
```

En la primera ejecución se descarga la release compatible, se verifica y se configura automáticamente `patchelf` (se instala si hace falta).

## Qué hace

| Función | Comportamiento |
| --- | --- |
| Instalación | Descarga la release de GitHub que corresponde exactamente a la versión del paquete npm. |
| Integridad | Comprueba el SHA-256 del tarball contra `release-checksums.json`, incluido en el paquete npm. |
| Runtime | Instala el binario y las bibliotecas musl, `libgcc` y `libstdc++` bajo `~/.opencode/`. |
| Actualización | Consulta npm al ejecutar `opencode`. Si existe una versión nueva, instala el paquete, reinicia el wrapper y descarga el runtime coincidente. |
| Recuperación | Si falla npm o la red, conserva y ejecuta la instalación que ya funciona. |
| Compatibilidad | Desactiva el auto-update interno de OpenCode para no reemplazar el binario preparado para Termux. |

## Flujo de ejecución

```text
opencode
  │
  ├─ ¿runtime completo y versión instalada = versión del paquete npm?
  │     ├─ no → descargar release → verificar SHA-256 → probar binario → activar runtime
  │     └─ sí → continuar
  │
  ├─ consultar la versión latest de npm (máximo 10 s)
  │     ├─ hay una versión nueva → npm install → reiniciar wrapper → instalar runtime de esa versión
  │     └─ no disponible/falla → conservar la versión actual
  │
  └─ ejecutar ~/.opencode/opencode
```

El archivo `~/.opencode/.opencode-termux-version` vincula el runtime instalado con la versión del paquete npm. Esto evita ejecutar un binario antiguo después de una actualización.

## Publicación automática

El workflow [Build and publish Termux package](.github/workflows/auto-update.yml) se ejecuta cada seis horas y también puede iniciarse manualmente.

1. Consulta la última release oficial de OpenCode mediante la API de GitHub.
2. Obtiene `opencode-linux-arm64-musl.tar.gz` y valida su SHA-256 publicado por GitHub.
3. Añade bibliotecas ARM64 de Alpine 3.21 para formar el runtime de Termux.
4. Crea `opencode-termux-aarch64.tar.gz` y registra su SHA-256 en `release-checksums.json`.
5. Publica el paquete en npm, crea la GitHub Release y confirma los metadatos generados en el repositorio.

Las ejecuciones se serializan para impedir dos publicaciones simultáneas. Si npm ya tiene una versión pero falta su release, el workflow se detiene en lugar de crear un artefacto cuyo checksum no coincida.

## Requisitos

- Android con [Termux](https://f-droid.org/en/packages/com.termux/)
- Arquitectura ARM64/aarch64
- Node.js 14 o superior y npm (`pkg install nodejs`)
- Conexión a Internet para la primera instalación y para las actualizaciones

## Actualizar o reparar

Normalmente basta con ejecutar `opencode`; el wrapper busca actualizaciones automáticamente.

```bash
# Ver la última versión publicada
npm view opencode-termux version

# Actualizar el paquete inmediatamente
npm install -g opencode-termux@latest
opencode

# Forzar una reinstalación del runtime sin borrar una copia funcional primero
rm -f ~/.opencode/.opencode-termux-version
opencode
```

Si `patchelf` no puede instalarse automáticamente:

```bash
pkg install patchelf
opencode
```

## Desinstalación

```bash
npm uninstall -g opencode-termux
rm -rf ~/.opencode
```

El segundo comando elimina el runtime administrado por este paquete. La configuración de OpenCode, si existe, puede estar en `~/.config/opencode` y se conserva.

## Estructura del proyecto

```text
bin/opencode                       Wrapper de actualización y arranque
install.js                          Instalador verificado y activación del runtime
release-checksums.json              SHA-256 de la release asociada al paquete npm
scripts/build-android-release.sh    Empaquetador reproducible para ARM64/Termux
.github/workflows/auto-update.yml   Detección y publicación automática
```

## Licencia

[MIT](LICENSE)
