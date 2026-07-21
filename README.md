# ⚡ opencode-termux

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Termux-green?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-aarch64-blue?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/npm/v/opencode-termux?style=for-the-badge&color=red" alt="npm version">
  <img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/auto-update.yml?style=for-the-badge&label=auto-update" alt="Workflow status">
  <img src="https://img.shields.io/npm/dt/opencode-termux?style=for-the-badge&color=orange" alt="downloads">
</p>

<p align="center">
  <b>OpenCode AI assistant compilado para Android Termux (aarch64)</b><br>
  <sub>Con auto-actualización automática cada vez que ejecutas <code>opencode</code></sub>
</p>

---

## 🚀 Instalación

```bash
npm install -g opencode-termux
```

Una vez instalado, simplemente ejecuta:

```bash
opencode
```

> **¡Eso es todo!** El wrapper se encarga de todo: descarga el binario, configura las librerías musl y lanza OpenCode.

---

## ✨ Características

| Característica | Descripción |
|----------------|-------------|
| 🔧 **Auto-setup** | La primera ejecución descarga y configura todo automáticamente |
| 🔄 **Auto-actualización** | Verifica nuevas versiones en cada ejecución y actualiza en segundo plano |
| 🛡️ **Updates oficiales deshabilitados** | Previene que el binario oficial rompa la compatibilidad con Termux |
| 📦 **Sin root** | Funciona completamente sin permisos de root |
| ⚡ **Rápido** | Las actualizaciones son silenciosas y no interrumpen tu flujo de trabajo |

---

## 📁 Estructura del Proyecto

```
opencode-termux/
├── .github/
│   └── workflows/
│       └── auto-update.yml    # GitHub Action: publica nuevas versiones automáticamente
├── bin/
│   └── opencode              # Wrapper bash: auto-update + lanza el binario
├── install.js                # Instalador: descarga binario + patchelf + symlinks
├── package.json              # Configuración npm (versión = versión de opencode)
└── README.md
```

---

## 🔍 ¿Cómo funciona?

### Flujo completo

```
opencode
    │
    ▼
┌─────────────────────────┐
│  ¿lib/opencode existe?  │
└────────┬────────────────┘
         │
    NO ──┼── SÍ
    │    │
    ▼    ▼
┌──────────┐  ┌───────────────────────┐
│install.js│  │¿Versión desactualizada?│
│descarga  │  └────────┬──────────────┘
│todo      │           │
└──────────┘  NO ──────┼── SÍ
                  │    │
                  ▼    ▼
               ┌────┐ ┌───────────────────────┐
               │exec│ │npm install -g latest   │
               │    │ │rm binario viejo        │
               │    │ │install.js → nuevo      │
               │    │ │exec                    │
               └────┘ └───────────────────────┘
```

### 1️⃣ Primera ejecución

Cuando ejecutas `opencode` por primera vez:

1. **`bin/opencode`** resuelve symlinks para encontrar la ruta real del paquete
2. Detecta que `lib/opencode` no existe
3. Ejecuta **`install.js`** que:
   - Descarga `opencode-termux-aarch64.tar.gz` desde [GitHub Releases](https://github.com/C04-wq/opencode-termux/releases)
   - Extrae el binario y 5 librerías musl a `lib/`
   - Ejecuta `patchelf` para configurar el interpreter musl
   - Crea symlinks en `~/.opencode/lib/`
4. Lanza el binario con las variables de entorno necesarias

### 2️⃣ Ejecuciones siguientes

```
bin/opencode
  → lib/opencode existe ✓
  → Versión local == Versión npm ✓
  → exec lib/opencode (sin cambios)
```

### 3️⃣ Cuando hay nueva versión

**GitHub Action** (cada 6 horas):
```
1. Detecta nueva versión de opencode oficial
2. Descarga binario nuevo + libs musl del release anterior
3. Crea nuevo tarball = binario nuevo + libs musl
4. Publica en npm (opencode-termux@vNuevaVersión)
5. Crea release en GitHub
6. Git commit + push
```

**En tu teléfono** (próxima ejecución):
```
bin/opencode
  → CURRENT=1.18.4 ≠ LATEST=1.18.5
  → "Instalando actualización v1.18.5..."
  → npm install -g opencode-termux@latest
  → rm binario viejo
  → install.js descarga nuevo binario
  → exec v1.18.5
```

---

## ⚙️ Variables de Entorno

| Variable | Valor | Propósito |
|----------|-------|-----------|
| `OPENCODE_DISABLE_AUTOUPDATE` | `1` | Desactiva actualizaciones oficiales de opencode |
| `LD_PRELOAD` | `~/.opencode/lib/ld-musl-aarch64.so.1` | Carga el runtime musl |
| `LD_LIBRARY_PATH` | `~/.opencode/lib/` | Ruta a las librerías compartidas |
| `SSL_CERT_FILE` | `/data/data/com.termux/files/usr/etc/tls/cert.pem` | Certificados SSL de Termux |

---

## 📋 Requisitos

- **SO**: Android con [Termux](https://f-droid.org/es/packages/com.termux/)
- **Arquitectura**: ARM64 (aarch64)
- **Conexión**: Internet (para instalación y actualizaciones)
- **Node.js**: Instalado en Termux (`pkg install nodejs`)
- **npm**: Incluido con Node.js

---

## 🛠️ Solución de Problemas

### El binario no se descarga

```bash
# Verificar que la conexión funciona
curl -s https://github.com | head -1

# Reinstalar manualmente
cd ~/opencode-termux
node install.js
```

### Error de patchelf

```bash
# Instalar patchelf
pkg install patchelf

# Re-ejecutar
opencode
```

### La actualización falla

```bash
# Forzar reinstalación limpia
rm -rf ~/opencode-termux/lib
opencode
```

---

## 🔄 Actualización Manual

```bash
# Verificar versión actual
npm view opencode-termux version

# Forzar actualización
npm install -g opencode-termux@latest --force
rm -f ~/opencode-termux/lib/opencode
opencode
```

---

## 📄 Licencia

[MIT](LICENSE)

---

<p align="center">
  <sub>Hecho con ❤️ para la comunidad de Termux</sub>
</p>
