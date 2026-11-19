<!--
  Gardez ce document synchronisé avec README.md, install.sh, manager.sh,
  uninstall.sh, scripts/, release-checksums.json et .github/workflows/.
-->

<p align="center">
  <img src="./opencode-logo.svg" alt="Logo OpenCode" width="88" height="110">
</p>

<h1 align="center">OpenCode pour Termux</h1>

<p align="center">
  <strong>Agent de programmation IA OpenCode exécuté nativement dans Android Termux.</strong><br>
  Empaquetage de l’environnement d’exécution ARM64 · Vérification SHA-256 · Installation gérée · Mises à jour avec consentement
</p>

<p align="center">
  <a href="./README.md">Español</a> · <a href="./README.en.md">English</a> · <a href="./README.fr.md">Français</a>
</p>

<p align="center">
  <a href="https://github.com/C04-wq/opencode-termux/releases/latest"><img src="https://img.shields.io/github/v/release/C04-wq/opencode-termux?display_name=tag&style=for-the-badge" alt="Dernière version"></a>
  <a href="https://github.com/C04-wq/opencode-termux/actions/workflows/validate.yml"><img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/validate.yml?branch=main&label=CI&style=for-the-badge" alt="Workflow de validation"></a>
  <a href="https://github.com/C04-wq/opencode-termux/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/release.yml?branch=main&label=Build%20release&style=for-the-badge" alt="Workflow de release"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/github/license/C04-wq/opencode-termux?style=for-the-badge" alt="Licence MIT"></a>
</p>


<p align="center">
  <a href="#-à-propos-du-projet">Projet</a> ·
  <a href="#-prérequis">Prérequis</a> ·
  <a href="#-installation">Installation</a> ·
  <a href="#-mises-à-jour">Mises à jour</a> ·
  <a href="#-cli-de-gestion">CLI de gestion</a> ·
  <a href="#-présentation-technique">Présentation technique</a> ·
  <a href="#-dépannage">Dépannage</a>
</p>

---

## 📱 À propos du projet

[OpenCode](https://opencode.ai/) est un agent de programmation open source fonctionnant dans le terminal. Ce dépôt empaquette la version officielle **Linux ARM64 musl** d’OpenCode et adapte son environnement d’exécution afin qu’il fonctionne directement sous **Android [Termux](https://termux.dev/)**.

Android n’est pas une distribution Linux conventionnelle : sa bibliothèque C, son arborescence de fichiers, ses certificats et sa configuration DNS diffèrent de l’environnement attendu par un binaire Linux standard. Ce projet comble ces différences grâce à un environnement musl embarqué, un chemin de résolution DNS adapté à Termux, un lanceur et un gestionnaire d’installation et de mise à jour.

Le résultat est une installation directe dans Termux. Aucun conteneur proot, machine virtuelle, système Linux de bureau, Node.js ou npm n’est nécessaire sur l’appareil.

> [!IMPORTANT]
> Il s’agit d’une **adaptation communautaire non officielle pour Termux**. OpenCode est développé en amont par [anomalyco/opencode](https://github.com/anomalyco/opencode). Ce dépôt prend en charge l’empaquetage Android/Termux, l’intégration de l’environnement d’exécution et l’installateur, et non l’application OpenCode en amont ni ses fournisseurs d’IA.

### Fonctionnalités principales

- **Exécution native dans Termux :** fonctionne directement dans Termux, sans proot ni machine virtuelle Linux.
- **Prise en charge ARM64 :** cible les appareils Android dont l’environnement Termux indique `aarch64`.
- **Détection des versions entre versions majeures :** sélectionne la dernière version stable d’OpenCode toutes versions majeures confondues (par exemple, de 1.x à 2.x).
- **Paquet vérifié :** contrôle l’archive téléchargée avec le condensat SHA-256 enregistré dans ce dépôt avant extraction.
- **Environnement musl intégré :** inclut le chargeur et les bibliothèques nécessaires ; aucun `patchelf`, Node.js ou npm n’est requis sur le téléphone.
- **Intégration réseau Termux :** utilise la configuration DNS et le bundle de certificats CA de Termux.
- **Mises à jour interactives avec consentement :** recherche une version plus récente au lancement interactif d’OpenCode et demande confirmation avant l’installation.
- **Commande de gestion :** permet d’installer, mettre à jour, désinstaller, inspecter et diagnostiquer l’installation gérée.
- **Installation défensive :** valide le paquet, prépare les fichiers avant activation, conserve l’environnement précédent pendant le remplacement et tente un retour arrière en cas d’échec de l’activation ou du contrôle final.
- **Préservation des données :** le désinstallateur supprime uniquement l’environnement géré et ses lanceurs.

## 📸 Captures d’écran

<p align="center">
  <img src="./screenshots/screenshot-1.png" alt="OpenCode exécuté dans Termux — capture 1" width="48%">
  <img src="./screenshots/screenshot-2.png" alt="OpenCode exécuté dans Termux — capture 2" width="48%">
</p>
<p align="center">
  <img src="./screenshots/screenshot-3.png" alt="OpenCode exécuté dans Termux — capture 3" width="48%">
  <img src="./screenshots/screenshot-4.png" alt="OpenCode exécuté dans Termux — capture 4" width="48%">
</p>

## ⚙️ Prérequis

| Prérequis | Détails |
| --- | --- |
| Appareil | Appareil Android exécutant Termux |
| Architecture | **ARM64 / `aarch64` uniquement** |
| Réseau | Accès Internet pour l’installation, les téléchargements GitHub Releases, les vérifications de mise à jour et l’accès aux fournisseurs d’IA |
| Commande initiale | `curl` doit être disponible pour exécuter l’installateur en une ligne |
| Outils | Bash, Git, curl, tar et `sha256sum` (fourni par `coreutils`) |
| Fichiers Termux | Bundle de certificats CA et configuration du résolveur DNS |

L’installateur utilise le gestionnaire de paquets Termux `pkg` pour installer les outils et paquets manquants, notamment Git, `ca-certificates` et `resolv-conf`. La commande d’installation elle-même nécessite que `curl` soit déjà installé.

### Environnements non pris en charge

Ce paquet ne prend actuellement **pas en charge** :

- ARM 32 bits (`arm` / `armv7`)
- Les appareils Android x86 ou x86_64
- Les shells Android autres que Termux ou les autres environnements de terminal Android
- Linux de bureau, macOS ou Windows

La compilation et l’automatisation des releases ciblent spécifiquement Termux ARM64.

## 🚀 Installation

1. Installez et ouvrez Termux depuis une source fiable.
2. Ouvrez le terminal Termux.
3. Exécutez :

```bash
curl -fsSL https://raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh | bash
```

4. Lorsque l’installation est terminée, lancez OpenCode :

```bash
opencode
```

Vérifiez la version installée ou consultez les options :

```bash
opencode --version
opencode --help
```

### Que fait l’installateur ?

1. **Vérifie la plateforme.** Il exige que `uname -m` renvoie `aarch64`.
2. **Prépare le dépôt du projet.** Pour une installation via un pipeline, il utilise `$PREFIX/opt/opencode-termux`. S’il trouve une copie propre de ce dépôt dans un emplacement courant sous le répertoire personnel Termux, il la met à jour et la déplace si possible vers l’emplacement géré.
3. **Protège le travail local.** Une copie contenant des fichiers modifiés ou non suivis n’est pas écrasée ; l’installateur s’arrête et demande de valider ou de mettre de côté les modifications.
4. **Prépare les dépendances.** Il installe avec `pkg` Git, curl, tar, coreutils, les certificats CA et la prise en charge du résolveur lorsqu’ils sont absents.
5. **Lit les métadonnées de release.** La version OpenCode attendue et le condensat SHA-256 de l’archive proviennent de `release-checksums.json`.
6. **Télécharge la release.** Il récupère `opencode-termux-aarch64.tar.gz` depuis les GitHub Releases de ce dépôt via HTTPS.
7. **Vérifie le téléchargement.** Il calcule SHA-256 et refuse de continuer si le condensat ne correspond pas aux métadonnées épinglées.
8. **Valide le contenu de l’archive.** Il rejette les fichiers inattendus, entrées en double, traversées de chemins, liens dangereux et types de fichiers incorrects avant extraction.
9. **Prépare l’environnement.** Il place l’exécutable, le chargeur musl et les bibliothèques dans un emplacement temporaire.
10. **Active et teste.** Il remplace l’environnement géré, installe les lanceurs et vérifie que le binaire installé indique la version attendue.
11. **Protège l’installation précédente.** L’ancien environnement et les anciens lanceurs sont conservés pendant l’activation et restaurés si l’activation ou le contrôle final échoue.

Les commandes réussies restent silencieuses afin de rendre la sortie lisible. En cas d’échec, leur sortie capturée est affichée pour faciliter le diagnostic.

### Installations existantes et gestion des conflits

L’installateur est volontairement prudent : il ne supprime pas une commande ou un paquet simplement parce que son nom contient « OpenCode ».

Il peut remplacer les installations reconnues lorsque leur propriété peut être établie :

- L’ancien paquet npm global `opencode-termux` n’est supprimé que si ses métadonnées sont valides et si le lien symbolique `opencode` existant pointe à l’intérieur de ce paquet.
- Une liste restreinte de propriétaires de paquets Termux/dpkg est reconnue à partir des métadonnées de propriété : `opencode`, `opencode1`, `opencode-termux`, `opencode-wrapper` et `opencode1-wrapper`.
- Un ancien lanceur géré par ce projet (`opencode`, `opencode-termux-update` ou `opencode-termux`) est remplacé après reconnaissance de son contenu.

Si une commande existante est inconnue, copiée manuellement ou ne peut pas être attribuée en toute sécurité à l’une de ces installations, l’installateur s’arrête et n’y touche pas. Identifiez et supprimez cette installation vous-même uniquement après en avoir confirmé l’origine. Il n’effectue pas de nettoyage global de tous les fichiers portant un nom similaire (par exemple, des binaires `opencode2` arbitraires), des paquets npm sans rapport ou des répertoires étrangers au projet.

L’installateur ne supprime pas non plus les paramètres, sessions, projets ou identifiants des fournisseurs OpenCode.

### Emplacements d’installation

| Composant | Chemin |
| --- | --- |
| Copie du dépôt | `$PREFIX/opt/opencode-termux` |
| Environnement OpenCode et bibliothèques | `$PREFIX/lib/opencode-termux/` |
| Commande OpenCode | `$PREFIX/bin/opencode` |
| CLI de gestion | `$PREFIX/bin/opencode-termux` |
| Programme de mise à jour interne | `$PREFIX/bin/opencode-termux-update` |
| Marqueur de version installée | `$PREFIX/lib/opencode-termux/.opencode-termux-version` |
| Marqueur du chemin du dépôt | `$PREFIX/lib/opencode-termux/.opencode-termux-repo-dir` |

Dans Termux, `$PREFIX` correspond généralement à `/data/data/com.termux/files/usr`. L’installateur définit les permissions d’exécution sur les trois commandes installées et vérifie qu’elles sont exécutables avant d’annoncer le succès.

Conservez la copie gérée du dépôt : la commande de mise à jour l’utilise pour récupérer les modifications et relancer l’installateur.

## 🔄 Mises à jour

Il existe deux mécanismes de mise à jour liés, mais distincts.

### 1. Invite interactive de mise à jour d’OpenCode

Lorsque vous lancez `opencode` dans un terminal interactif, le lanceur consulte les métadonnées de release de la branche `main` pour rechercher une version plus récente de l’environnement OpenCode.

Si une nouvelle version est disponible, un menu s’affiche :

```text
A new OpenCode version is available: 2.x.x (installed: 2.x.x).

Use ↑/↓ to choose and Enter to confirm.

● Install update now
  Wait for the next version
```

- **Install update now :** exécute le programme de mise à jour du projet, effectue une avance Git en fast-forward uniquement sur la copie gérée, puis relance l’installateur pour télécharger et vérifier le nouvel environnement.
- **Wait for the next version :** lance la version actuellement installée sans mise à jour.
- **Réseau indisponible :** la vérification est facultative ; une requête GitHub en échec n’empêche pas le démarrage de l’environnement installé.
- **Exécution non interactive :** le menu n’apparaît pas lorsque l’entrée ou la sortie standard ne sont pas des terminaux.

L’invite compare la version OpenCode installée à celle indiquée dans `release-checksums.json`. Il s’agit d’une invite concernant la **version de l’environnement d’exécution**, et non d’une notification générale de chaque modification des fichiers du dépôt. Une modification limitée au gestionnaire ou à l’installateur peut donc nécessiter une mise à jour manuelle du projet même si OpenCode n’a pas publié de nouvelle version.

### 2. Mettre à jour manuellement le projet et l’environnement

Pour récupérer le code le plus récent du projet et réinstaller l’environnement vérifié :

```bash
opencode-termux update
```

Cette commande effectue une mise à jour Git en fast-forward uniquement (`git pull --ff-only`) dans la copie gérée, puis exécute son `install.sh`. Elle met à jour le gestionnaire, le lanceur, le programme de mise à jour et l’environnement selon le dépôt récupéré et ses métadonnées de release.

Le programme de mise à jour définit le paramètre Git local `core.filemode=false`. Cela évite de considérer les différences de permissions seules comme des modifications de code sous Termux, tout en continuant à détecter les changements de contenu.

Si des modifications locales ou des fichiers non suivis empêchent l’avance rapide, l’opération s’arrête au lieu d’écraser ces fichiers. Inspectez la copie :

```bash
git -C "$PREFIX/opt/opencode-termux" status --short
```

Validez, mettez de côté ou résolvez vos modifications locales avant de réessayer.

### 3. Relancer l’installateur pour réparer l’installation

Vous pouvez également relancer l’installateur :

```bash
curl -fsSL https://raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh | bash
```

Il détecte la copie gérée et relance la procédure d’installation. Cette méthode permet de réparer des lanceurs manquants ou leurs permissions d’exécution, ainsi que d’installer la version indiquée par les métadonnées de release de la copie locale.

> **Important :** le lanceur désactive le programme de mise à jour intégré d’OpenCode avec `OPENCODE_DISABLE_AUTOUPDATE=1`. Cela empêche le mécanisme upstream de remplacer l’environnement géré par Termux en dehors du processus d’installation vérifié du projet.

## 🧰 CLI de gestion

L’installateur fournit une commande distincte, `opencode-termux`. Elle gère ce paquet Termux ; ce n’est pas l’application OpenCode elle-même.

Afficher l’aide :

```bash
opencode-termux
# ou
opencode-termux --help
```

### Commandes

| Commande | Forme avec option | Description |
| --- | --- | --- |
| `install` | `--install` | Installe ou répare l’environnement géré à partir de la copie existante. |
| `update` | `--update` | Met à jour la copie en fast-forward et réinstalle l’environnement vérifié. |
| `uninstall` | `--uninstall` | Lance le désinstallateur du projet, qui demande confirmation. |
| `version` | `--version`, `-V` | Affiche la version du gestionnaire et celle d’OpenCode installé, le cas échéant. |
| `status` | `--status` | Indique si l’environnement est installé et affiche ses principaux chemins. |
| `doctor` | `--doctor` | Vérifie l’architecture, les dépendances, les fichiers, les lanceurs, les permissions, les certificats, le DNS et le démarrage. |
| `help` | `--help`, `-h` | Affiche l’aide. |

Exemples :

```bash
opencode-termux status
opencode-termux version
opencode-termux doctor
opencode-termux update
```

### Diagnostic avec `doctor`

Exécutez :

```bash
opencode-termux doctor
```

Le diagnostic vérifie :

- Que l’architecture de l’appareil est `aarch64`.
- Que les commandes requises (`git`, `curl`, `tar` et `sha256sum`) sont disponibles.
- Que tous les fichiers attendus de l’environnement existent et ne sont pas vides.
- Que l’exécutable OpenCode et le chargeur musl possèdent les permissions d’exécution.
- Que le marqueur de version existe et respecte un format valide.
- Que le lanceur OpenCode est bien celui géré par le projet.
- Que la commande de gestion existe, est exécutable et contient le marqueur de propriété du projet.
- Que le programme de mise à jour interne existe et est identifiable.
- Que le bundle CA et la configuration du résolveur Termux sont présents.
- Que l’exécutable OpenCode démarre et indique la version enregistrée dans son marqueur.

Les résultats individuels sont affichés sous forme `OK` / `FAIL`. Le code de sortie est non nul si un contrôle échoue. Il s’agit d’un diagnostic local de l’installation : il ne vérifie pas les clés API, les comptes fournisseurs, l’accès à tous les services d’IA ni l’état du projet OpenCode en amont.

## 🧩 Présentation technique

Ce projet empaquette l’exécutable OpenCode upstream avec un petit environnement musl adapté à Termux.

### Construction de l’environnement d’exécution

1. **Binaire upstream :** télécharge l’archive officielle `opencode-linux-arm64-musl.tar.gz` depuis les [releases OpenCode](https://github.com/anomalyco/opencode/releases).
2. **Intégrité upstream :** le constructeur vérifie l’archive officielle avec le condensat SHA-256 fourni par les métadonnées de release upstream.
3. **musl :** compile musl 1.2.6 pour AArch64 en remplaçant le chemin conventionnel `/etc/resolv.conf` par celui de Termux : `/data/data/com.termux/files/usr/etc/resolv.conf`.
4. **Bibliothèques :** empaquette le chargeur musl, musl libc, `libgcc_s.so.1` et `libstdc++.so.6`.
5. **Interpréteur ELF :** modifie le `PT_INTERP` de l’ELF OpenCode pour pointer vers le chemin absolu du chargeur musl embarqué.
6. **Exécution directe :** le lanceur exécute directement l’ELF OpenCode. C’est intentionnel : OpenCode 2.x réexécute `/proc/self/exe` au démarrage de son serveur en arrière-plan. Si le chargeur était lancé comme wrapper, ce chemin désignerait le chargeur et non l’exécutable OpenCode.
7. **Environnement Termux :** le lanceur efface le `LD_PRELOAD` hérité, définit `SSL_CERT_FILE` sur le bundle CA Termux et ajoute le répertoire runtime embarqué à `LD_LIBRARY_PATH`.
8. **Mises à jour gérées :** `OPENCODE_DISABLE_AUTOUPDATE=1` désactive le programme de mise à jour intégré d’OpenCode afin que le remplacement de l’environnement reste sous le contrôle de l’installateur du projet.

### Contenu de l’archive runtime

L’archive de release possède une structure plate et strictement définie :

| Entrée | Rôle |
| --- | --- |
| `opencode` | Exécutable OpenCode AArch64 upstream, adapté à l’interpréteur embarqué |
| `ld-musl-aarch64.so.1` | Chargeur dynamique musl |
| `libc.musl-aarch64.so.1` | Bibliothèque C musl |
| `libgcc_s.so.1` | Bibliothèque de support runtime GCC |
| `libstdc++.so.6.runtime` | Bibliothèque runtime GNU C++ embarquée |
| `libstdc++.so.6` | Lien symbolique relatif vers `libstdc++.so.6.runtime` |

Le validateur exige exactement ces six entrées. Il rejette les chemins supplémentaires, doublons, répertoires, liens physiques, liens symboliques inattendus, cibles de liens dangereuses et traversées de chemins avant toute extraction.

### Structure du dépôt

```text
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── validate.yml
│       ├── release.yml
│       └── toolchain-updates.yml
├── scripts/
│   ├── build-android-release.sh
│   ├── setup-alpine-chroot.sh
│   ├── resolve-opencode-release.mjs
│   ├── validate-runtime-archive.sh
│   ├── smoke-test-runtime-archive.sh
│   └── tests et outils de toolchain
├── screenshots/
├── install.sh
├── manager.sh
├── opencode-termux
├── uninstall.sh
├── release-checksums.json
├── opencode-logo.svg
├── README.md
├── README.en.md
├── README.es.md
└── README.fr.md
```

- `install.sh` : bootstrap, préparation des dépendances, installation runtime vérifiée et génération des lanceurs.
- `manager.sh` / `opencode-termux` : CLI de gestion. Le point d’entrée du dépôt et l’implémentation canonique sont synchronisés et vérifiés par CI.
- `uninstall.sh` : suppression avec confirmation de l’environnement géré et de ses lanceurs.
- `release-checksums.json` : version runtime actuelle et condensat d’archive attendu.
- `scripts/build-android-release.sh` : construit l’archive Termux ARM64.
- `scripts/validate-runtime-archive.sh` : valide la structure de l’archive avant extraction.
- `scripts/smoke-test-runtime-archive.sh` : teste l’exécutable AArch64 empaqueté sous QEMU.
- `scripts/resolve-opencode-release.mjs` : trouve et valide la dernière release stable OpenCode upstream.
- `scripts/setup-alpine-chroot.sh` : prépare l’environnement Alpine de vérification des paquets utilisé par CI.

## 🔐 Sécurité et intégrité

Le processus d’installation est conçu pour échouer de manière sûre lorsqu’il est impossible d’établir l’intégrité du paquet ou la propriété des fichiers.

- L’archive runtime est téléchargée via HTTPS ; curl est limité à HTTPS pour la requête initiale et ses redirections.
- L’archive doit correspondre au condensat SHA-256 de `release-checksums.json`.
- Le constructeur de release vérifie indépendamment le condensat de l’archive officielle upstream avant l’empaquetage.
- Le validateur inspecte chaque entrée avant extraction et n’autorise que le lien symbolique relatif attendu pour la bibliothèque C++.
- L’installateur n’écrase pas les commandes inconnues dans le répertoire `bin` de Termux.
- Le nettoyage de l’ancien paquet npm dépend de ses métadonnées et de la propriété du lien symbolique ; le nettoyage des paquets Termux dépend des informations dpkg et d’une liste d’autorisation explicite.
- L’installation prépare le nouvel environnement et conserve l’ancien pendant l’activation, avec une procédure de retour arrière en cas d’échec.
- Le désinstallateur vérifie le marqueur runtime et l’identité des lanceurs avant leur suppression.
- GitHub Actions utilise des permissions explicites, des SHA de commits épinglés pour les actions tierces et n’expose pas les identifiants d’écriture aux étapes de build et de test.

**Ce que cela ne garantit pas :** la vérification SHA-256 confirme que l’archive téléchargée correspond au condensat publié par ce dépôt ; elle ne constitue pas une signature numérique indépendante. Le projet ne peut pas non plus garantir la sécurité ou la disponibilité d’OpenCode upstream, des fournisseurs d’IA tiers, des services API ou des paquets Termux installés par l’utilisateur. Pour un audit indépendant, examinez les releases et les modifications du code avant l’installation.

## 🤖 Automatisation des releases et CI

GitHub Actions construit les releases et valide l’installateur et l’environnement runtime.

| Workflow | Déclencheur | Objectif |
| --- | --- | --- |
| [Validate Termux installer](.github/workflows/validate.yml) | Push, pull requests et lancement manuel | Contrôles de syntaxe, ShellCheck, YAML, métadonnées de release, régressions, sécurité des archives et tests runtime ARM64 sous QEMU. |
| [Build and publish GitHub release](.github/workflows/release.yml) | Toutes les 6 heures, push pertinents vers `main` ou lancement manuel | Résout la dernière release stable upstream, construit et teste l’archive Termux, publie les ressources et met à jour les condensats. |
| [Check toolchain updates](.github/workflows/toolchain-updates.yml) | Planification quotidienne, push/PR pertinents ou lancement manuel | Vérifie les branches stables Alpine, valide un build candidat et ouvre une pull request révisable lorsque la branche de build épinglée avance. |

### Sélection des releases

Le résolveur de releases :

- Récupère toutes les pages de releases GitHub upstream.
- Compare numériquement les versions sémantiques stables, y compris entre versions majeures.
- Exclut les brouillons, préversions et tags ne respectant pas le format stable `vMAJOR.MINOR.PATCH`.
- Exige que la dernière release stable publie l’archive officielle ARM64 musl et un condensat SHA-256 valide.
- Échoue au lieu de sélectionner silencieusement une version plus ancienne si la dernière release stable ne contient pas la ressource ou le condensat requis.

Chaque release du projet publie :

- `opencode-termux-aarch64.tar.gz` — l’environnement empaqueté.
- `opencode-termux-aarch64.tar.gz.sha256` — le checksum de l’archive.

Le workflow met à jour `release-checksums.json` avec la version et le condensat utilisés par l’installateur.

### Couverture de validation

La CI comprend :

- Vérifications de syntaxe Bash et ShellCheck.
- Vérifications de syntaxe Node.js et tests unitaires/de régression des utilitaires release et toolchain.
- Analyse YAML des workflows et de la configuration Dependabot.
- Vérifications de synchronisation entre le point d’entrée du gestionnaire et son implémentation canonique.
- Tests de détection des propriétaires de paquets dpkg.
- Tests d’archives couvrant les archives valides, fichiers inattendus, traversées, liens symboliques dangereux, mauvaises cibles de liens et liens physiques.
- Test runtime ARM64 sous QEMU : inspection de l’architecture ELF et de l’interpréteur, exécution de `opencode --version` et vérification que `opencode serve` reste actif jusqu’au délai maximal du test.

> **Limite des tests :** QEMU fournit une couverture automatisée ARM64 utile, mais ne remplace pas les tests de chaque release sur un appareil Android physique avec Termux. La CI ne prouve pas la compatibilité avec toutes les versions Android, tous les appareils, réseaux, fournisseurs ou configurations utilisateur.

Node.js est utilisé uniquement par les scripts GitHub Actions hébergés. Il n’est pas requis sur l’appareil Android.

## 🛠️ Dépannage

### `opencode: command not found`

Vérifiez que le lanceur géré existe, puis relancez l’installateur :

```bash
ls -l "$PREFIX/bin/opencode"
bash "$PREFIX/opt/opencode-termux/install.sh"
hash -r
opencode --version
```

Vous pouvez également relancer l’installateur curl en une ligne ; il détectera et réutilisera la copie gérée.

### `opencode-termux: command not found`

La CLI de gestion est installée dans `$PREFIX/bin/opencode-termux`. Vérifiez son existence et la présence du répertoire `bin` de Termux dans votre `PATH` :

```bash
printf '%s\n' "$PATH"
ls -l "$PREFIX/bin/opencode-termux"
```

Relancez ensuite l’installateur pour restaurer le gestionnaire et ses permissions :

```bash
bash "$PREFIX/opt/opencode-termux/install.sh"
hash -r
opencode-termux --help
```

### `permission denied`

L’installateur applique le mode `755` au lanceur OpenCode, au gestionnaire et au programme de mise à jour après leur installation dans leurs chemins définitifs. Relancez l’installateur :

```bash
bash "$PREFIX/opt/opencode-termux/install.sh"
ls -l "$PREFIX/bin/opencode" "$PREFIX/bin/opencode-termux" "$PREFIX/bin/opencode-termux-update"
```

### Architecture non prise en charge

Vérifiez l’architecture signalée par Termux :

```bash
uname -m
dpkg --print-architecture
```

L’appareil pris en charge doit indiquer `aarch64`. Ce paquet ne fonctionne pas sur ARM 32 bits ni sur les appareils x86.

### Erreurs de téléchargement, TLS ou DNS

Mettez à jour les paquets Termux et vérifiez l’accès à GitHub :

```bash
pkg update
pkg install git curl tar coreutils ca-certificates resolv-conf
curl -I https://github.com
```

L’installateur vérifie le bundle CA et la configuration du résolveur Termux. Ne contournez pas la vérification SHA-256 si un téléchargement échoue ou si le condensat ne correspond pas.

### La mise à jour ne peut pas avancer en fast-forward

Le programme de mise à jour utilise volontairement `git pull --ff-only`. Inspectez la copie :

```bash
git -C "$PREFIX/opt/opencode-termux" status --short
```

Validez, mettez de côté ou résolvez les modifications locales avant de réessayer `opencode-termux update`. Le programme de mise à jour ne force pas de réinitialisation du dépôt.

### Le menu interactif de mise à jour n’apparaît pas

Le menu s’affiche uniquement si toutes les conditions suivantes sont réunies :

- OpenCode est lancé depuis un terminal interactif.
- Le lanceur peut accéder aux métadonnées de release du dépôt.
- Les métadonnées contiennent une version valide plus récente que celle installée.

Une modification limitée au dépôt ne change pas nécessairement la version runtime d’OpenCode. Pour récupérer directement les modifications du gestionnaire ou de l’installateur, utilisez :

```bash
opencode-termux update
```

### Les commandes shell d’OpenCode se comportent mal

Le lanceur efface le `LD_PRELOAD` hérité et configure le chemin des bibliothèques runtime embarquées. Commencez par mettre à jour le projet :

```bash
opencode-termux update
opencode-termux doctor
```

Si le problème persiste, ouvrez une [issue](https://github.com/C04-wq/opencode-termux/issues) avec votre version Android, le résultat de `uname -m`, la version OpenCode, la commande concernée et le message d’erreur complet. Supprimez les clés API, jetons et autres secrets des journaux avant de les partager.

## 🗑️ Désinstallation

Pour supprimer l’installation Termux gérée :

```bash
opencode-termux uninstall
```

Le désinstallateur demande confirmation. Vous pouvez également le lancer directement depuis la copie du dépôt :

```bash
bash "$PREFIX/opt/opencode-termux/uninstall.sh"
```

Après confirmation, il supprime uniquement :

- `$PREFIX/lib/opencode-termux` — l’environnement géré et ses marqueurs.
- `$PREFIX/bin/opencode` — le lanceur de ce projet.
- `$PREFIX/bin/opencode-termux-update` — le programme de mise à jour interne.
- `$PREFIX/bin/opencode-termux` — la CLI de gestion.

Il vérifie le marqueur runtime et l’identité des lanceurs avant toute suppression. Si la propriété ne peut pas être établie, il s’arrête et laisse l’installation intacte.

**Le désinstallateur ne supprime pas :**

- La copie du dépôt dans `$PREFIX/opt/opencode-termux`.
- Les paquets Termux ou npm lui-même.
- Les paramètres, sessions, projets ou identifiants des fournisseurs OpenCode.
- Les autres binaires ou installations ne faisant pas partie de cet environnement géré.

Si vous souhaitez également supprimer les sources du projet, supprimez vous-même la copie après la désinstallation et après avoir vérifié qu’elle ne contient aucun travail à conserver.

## 🤝 Contribution

Les issues, rapports de bogues et pull requests sont les bienvenus. Veuillez aligner les modifications sur la cible Termux ARM64 et ne pas affaiblir la validation des archives, la vérification des condensats, les contrôles de propriété ou le mécanisme de retour arrière.

### Validation locale

Depuis une copie du dépôt, exécutez les contrôles pertinents :

```bash
# Syntaxe shell
bash -n install.sh uninstall.sh manager.sh opencode-termux
bash -n scripts/build-android-release.sh scripts/setup-alpine-chroot.sh
bash -n scripts/validate-runtime-archive.sh scripts/smoke-test-runtime-archive.sh

# Syntaxe et tests JavaScript
node --check scripts/resolve-opencode-release.mjs
node --check scripts/check-toolchain-updates.mjs
node scripts/test-opencode-release-resolver.mjs
node scripts/test-toolchain-updates.mjs

# Tests de régression shell
bash scripts/test-package-owner.sh
bash scripts/test-runtime-archive.sh

# Analyse statique (nécessite ShellCheck)
shellcheck -S error install.sh uninstall.sh manager.sh opencode-termux scripts/*.sh
```

Le workflow de validation GitHub Actions exécute ces contrôles, ainsi que la validation YAML et le test runtime ARM64 sous QEMU.

### Directives de contribution

- Gardez le point d’entrée du gestionnaire (`opencode-termux`) synchronisé avec `manager.sh`.
- Gardez la structure de l’archive release et les métadonnées de checksum cohérentes avec l’installateur et le validateur.
- N’introduisez pas de téléchargements non vérifiés et ne contournez pas les contrôles de checksum upstream ou du projet.
- Préservez le chemin du résolveur Termux, la configuration de l’interpréteur ELF et le comportement d’exécution directe requis par le serveur en arrière-plan d’OpenCode.
- Documentez dans ce README les changements de comportement visibles par l’utilisateur.
- N’incluez jamais de clés API, jetons d’accès, identifiants personnels ou données privées dans les commits ou rapports d’issue.

## 📄 Licence et remerciements

Ce dépôt est distribué sous la [licence MIT](./LICENSE).

[OpenCode](https://github.com/anomalyco/opencode) est un projet upstream distinct maintenu par [anomalyco](https://github.com/anomalyco). Ce dépôt ne revendique pas la propriété de l’application upstream. Consultez le dépôt upstream pour son code source, sa licence, ses releases et les avis du projet.
