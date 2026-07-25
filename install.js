#!/usr/bin/env node
const { execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const { version: VERSION } = require("./package.json");
const { archiveSha256, version: checksumVersion } = require("./release-checksums.json");
const HOME = process.env.HOME;
const CERTIFICATE_FILE = "/data/data/com.termux/files/usr/etc/tls/cert.pem";
const RESOLVER_FILE = "/data/data/com.termux/files/usr/etc/resolv.conf";
const REQUIRED_FILES = [
  "opencode",
  "ld-musl-aarch64.so.1",
  "libc.musl-aarch64.so.1",
  "libgcc_s.so.1",
  "libstdc++.so.6",
  "libstdc++.so.6.0.33",
];

function message(text) {
  process.stdout.write(`  ◇ ${text}\n`);
}

function success(text) {
  process.stdout.write(`  ✓ ${text}\n`);
}

function commandExists(command) {
  return (process.env.PATH || "").split(":").some((directory) => {
    try {
      fs.accessSync(path.join(directory, command), fs.constants.X_OK);
      return true;
    } catch (_) {
      return false;
    }
  });
}

function commandError(error) {
  const output = Buffer.concat([error.stdout || Buffer.alloc(0), error.stderr || Buffer.alloc(0)]).toString().trim();
  return output ? output.split("\n").slice(-1)[0] : error.message;
}

function run(command, args, options = {}) {
  return execFileSync(command, args, { stdio: "pipe", ...options });
}

function ensureDependencies() {
  const packages = [];
  if (!commandExists("curl")) packages.push("curl");
  if (!commandExists("tar")) packages.push("tar");
  if (!commandExists("patchelf")) packages.push("patchelf");
  if (!commandExists("timeout")) packages.push("coreutils");
  if (!fs.existsSync(CERTIFICATE_FILE)) packages.push("ca-certificates");
  if (!fs.existsSync(RESOLVER_FILE)) packages.push("resolv-conf");
  if (packages.length === 0) return;
  if (!commandExists("pkg")) throw new Error(`missing required Termux tools: ${packages.join(", ")}`);

  message("Setting up Termux dependencies…");
  try {
    run("pkg", ["install", "-y", ...packages], { timeout: 180000 });
  } catch (error) {
    throw new Error(`could not install dependencies: ${commandError(error)}`);
  }

  const stillMissing = [
    !commandExists("curl") && "curl",
    !commandExists("tar") && "tar",
    !commandExists("patchelf") && "patchelf",
    !commandExists("timeout") && "coreutils",
    !fs.existsSync(CERTIFICATE_FILE) && "ca-certificates",
    !fs.existsSync(RESOLVER_FILE) && "resolv-conf",
  ].filter(Boolean);
  if (stillMissing.length) throw new Error(`missing dependencies after setup: ${stillMissing.join(", ")}`);
  success("Termux dependencies are ready");
}

if (process.arch !== "arm64") {
  console.error("Error: opencode-termux supports aarch64 only.");
  process.exit(1);
}
if (!HOME) {
  console.error("Error: HOME is not set.");
  process.exit(1);
}
if (checksumVersion !== VERSION) {
  console.error("Error: package checksum metadata does not match package.json.");
  process.exit(1);
}
if (!archiveSha256 || !/^[a-f0-9]{64}$/.test(archiveSha256)) {
  console.error("Error: this package was published without a valid release checksum.");
  process.exit(1);
}

const OPENCODE_DIR = path.join(HOME, ".opencode");
const VERSION_FILE = path.join(OPENCODE_DIR, ".opencode-termux-version");
const URL = `https://github.com/C04-wq/opencode-termux/releases/download/v${VERSION}/opencode-termux-aarch64.tar.gz`;

function hasRequiredFiles(directory) {
  return REQUIRED_FILES.every((file) => {
    try {
      return fs.statSync(path.join(directory, file)).size > 0;
    } catch (_) {
      return false;
    }
  });
}

function hasCompleteInstall(directory) {
  if (!hasRequiredFiles(directory)) return false;
  try {
    return fs.readFileSync(path.join(directory, ".opencode-termux-version"), "utf8").trim() === VERSION;
  } catch (_) {
    return false;
  }
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

try {
  ensureDependencies();
  if (process.argv.includes("--ensure-dependencies") || hasCompleteInstall(OPENCODE_DIR)) process.exit(0);

  const staging = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-termux-"));
  const archive = path.join(staging, "release.tar.gz");
  const extracted = path.join(staging, "files");
  try {
    message("Preparing OpenCode for Termux…");
    run("curl", ["--silent", "--show-error", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--retry", "3", "--retry-all-errors", "-o", archive, URL], { timeout: 300000 });
    if (sha256(archive) !== archiveSha256) throw new Error("downloaded archive checksum does not match the npm package metadata");

    fs.mkdirSync(extracted);
    run("tar", ["-xzf", archive, "-C", extracted], { timeout: 60000 });
    if (!hasRequiredFiles(extracted)) throw new Error("release archive is incomplete");

    const binary = path.join(extracted, "opencode");
    const interpreter = path.join(extracted, "ld-musl-aarch64.so.1");
    run("patchelf", ["--set-interpreter", interpreter, binary], { timeout: 15000 });
    execFileSync(binary, ["--version"], {
      stdio: "pipe",
      env: { ...process.env, LD_PRELOAD: interpreter, LD_LIBRARY_PATH: extracted, SSL_CERT_FILE: CERTIFICATE_FILE },
      timeout: 30000,
    });

    fs.mkdirSync(OPENCODE_DIR, { recursive: true });
    run("patchelf", ["--set-interpreter", path.join(OPENCODE_DIR, "ld-musl-aarch64.so.1"), binary], { timeout: 15000 });
    for (const file of REQUIRED_FILES) fs.renameSync(path.join(extracted, file), path.join(OPENCODE_DIR, file));
    fs.writeFileSync(VERSION_FILE, `${VERSION}\n`, { mode: 0o600 });
    success(`OpenCode ${VERSION} is ready`);
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exitCode = 1;
}
