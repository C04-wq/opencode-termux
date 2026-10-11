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
  "libstdc++.so.6.runtime",
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

function normalizeLibstdcxx(directory) {
  const runtime = path.join(directory, "libstdc++.so.6.runtime");
  const soname = path.join(directory, "libstdc++.so.6");

  // Older published archives contain the versioned Alpine library directly
  // (for example libstdc++.so.6.0.33) instead of the normalized runtime name.
  // The archive checksum is verified before this function is called.
  if (!fs.existsSync(runtime)) {
    const versioned = fs.readdirSync(directory)
      .filter((file) => /^libstdc\+\+\.so\.6(?:\.\d+)+$/.test(file))
      .sort()
      .pop();
    if (!versioned) return;
    fs.copyFileSync(path.join(directory, versioned), runtime);
    fs.chmodSync(runtime, 0o644);
  }

  try {
    const stat = fs.lstatSync(soname);
    if (stat.isSymbolicLink()) fs.unlinkSync(soname);
  } catch (_) {
    // Create the SONAME link below when it is absent.
  }
  if (!fs.existsSync(soname)) fs.symlinkSync("libstdc++.so.6.runtime", soname);
}

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
    normalizeLibstdcxx(extracted);
    if (!hasRequiredFiles(extracted)) throw new Error("release archive is incomplete");

    const binary = path.join(extracted, "opencode");
    const interpreter = path.join(extracted, "ld-musl-aarch64.so.1");
    run("patchelf", ["--set-interpreter", interpreter, binary], { timeout: 15000 });
    const extractedRuntimeEnv = {
      ...process.env,
      LD_LIBRARY_PATH: extracted,
      SSL_CERT_FILE: CERTIFICATE_FILE,
    };
    delete extractedRuntimeEnv.LD_PRELOAD;
    execFileSync(interpreter, ["--library-path", extracted, binary, "--version"], {
      stdio: "pipe",
      env: extractedRuntimeEnv,
      timeout: 30000,
    });

    // Prepare the complete runtime beside the destination so activation uses
    // directory renames on the same filesystem, not a sequence of live file writes.
    const activation = fs.mkdtempSync(path.join(HOME, ".opencode-termux-activate-"));
    let backup = null;
    try {
      for (const file of REQUIRED_FILES) {
        const source = path.join(extracted, file);
        const destination = path.join(activation, file);
        const sourceStat = fs.lstatSync(source);
        if (sourceStat.isSymbolicLink()) {
          fs.symlinkSync(fs.readlinkSync(source), destination);
        } else {
          fs.copyFileSync(source, destination);
          fs.chmodSync(destination, sourceStat.mode & 0o777);
        }
      }
      const stagedBinary = path.join(activation, "opencode");
      run("patchelf", ["--set-interpreter", path.join(OPENCODE_DIR, "ld-musl-aarch64.so.1"), stagedBinary], { timeout: 15000 });
      fs.writeFileSync(path.join(activation, ".opencode-termux-version"), `${VERSION}\n`, { mode: 0o600 });

      if (fs.existsSync(OPENCODE_DIR)) {
        backup = path.join(HOME, `.opencode-termux-backup-${process.pid}-${Date.now()}`);
        fs.renameSync(OPENCODE_DIR, backup);
      }
      try {
        fs.renameSync(activation, OPENCODE_DIR);
      } catch (activationError) {
        if (backup && !fs.existsSync(OPENCODE_DIR)) fs.renameSync(backup, OPENCODE_DIR);
        throw activationError;
      }
      try {
        const activeRuntimeEnv = {
          ...process.env,
          LD_LIBRARY_PATH: OPENCODE_DIR,
          SSL_CERT_FILE: CERTIFICATE_FILE,
        };
        delete activeRuntimeEnv.LD_PRELOAD;
        execFileSync(path.join(OPENCODE_DIR, "ld-musl-aarch64.so.1"), [
          "--library-path", OPENCODE_DIR, path.join(OPENCODE_DIR, "opencode"), "--version",
        ], {
          stdio: "pipe",
          env: activeRuntimeEnv,
          timeout: 30000,
        });
      } catch (runtimeError) {
        fs.renameSync(OPENCODE_DIR, activation);
        if (backup) fs.renameSync(backup, OPENCODE_DIR);
        throw new Error(`runtime failed verification at its final path: ${runtimeError.message}`);
      }
      if (backup) {
        try {
          fs.rmSync(backup, { recursive: true, force: true });
        } catch (_) {
          // The new runtime is active; a stale backup is safer than reporting
          // a failed installation after a successful activation.
        }
      }
      success(`OpenCode ${VERSION} is ready`);
    } finally {
      fs.rmSync(activation, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exitCode = 1;
}
