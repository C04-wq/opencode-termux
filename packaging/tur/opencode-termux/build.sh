TERMUX_PKG_HOMEPAGE=https://github.com/C04-wq/opencode-termux
TERMUX_PKG_DESCRIPTION="OpenCode AI coding agent launcher for Termux (aarch64)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="C04-wq"
TERMUX_PKG_VERSION=1.19.5
TERMUX_PKG_SRCURL=https://github.com/C04-wq/opencode-termux/releases/download/v${TERMUX_PKG_VERSION}/opencode-termux-aarch64.tar.gz
TERMUX_PKG_SHA256=6b670b9b1693e54ea831dfdde00ad2d062783594b79e438d29d59f28407056d0
TERMUX_PKG_DEPENDS="ca-certificates, resolv-conf"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_PLATFORM_INDEPENDENT=false

termux_step_make_install() {
    [[ "${TERMUX_ARCH}" == "aarch64" ]] || termux_error_exit "OpenCode Termux package currently supports aarch64 only."

    local runtime_dir="${TERMUX_PREFIX}/lib/opencode-termux"
    local required
    for required in opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6.runtime; do
        [[ -s "${TERMUX_PKG_SRCDIR}/${required}" ]] || termux_error_exit "Release archive is missing required file: ${required}"
    done

    install -d "${runtime_dir}"
    install -Dm755 "${TERMUX_PKG_SRCDIR}/opencode" "${runtime_dir}/opencode"
    install -Dm755 "${TERMUX_PKG_SRCDIR}/ld-musl-aarch64.so.1" "${runtime_dir}/ld-musl-aarch64.so.1"
    install -Dm755 "${TERMUX_PKG_SRCDIR}/libc.musl-aarch64.so.1" "${runtime_dir}/libc.musl-aarch64.so.1"
    install -Dm644 "${TERMUX_PKG_SRCDIR}/libgcc_s.so.1" "${runtime_dir}/libgcc_s.so.1"
    install -Dm644 "${TERMUX_PKG_SRCDIR}/libstdc++.so.6.runtime" "${runtime_dir}/libstdc++.so.6.runtime"
    ln -sfn libstdc++.so.6.runtime "${runtime_dir}/libstdc++.so.6"

    install -d "${TERMUX_PREFIX}/bin"
    cat > "${TERMUX_PREFIX}/bin/opencode" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
set -eu
unset LD_PRELOAD
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
RUNTIME_DIR="${PREFIX}/lib/opencode-termux"
export SSL_CERT_FILE="${SSL_CERT_FILE:-${PREFIX}/etc/tls/cert.pem}"
exec "${RUNTIME_DIR}/ld-musl-aarch64.so.1" --library-path "${RUNTIME_DIR}" "${RUNTIME_DIR}/opencode" "$@"
EOF
    chmod 0755 "${TERMUX_PREFIX}/bin/opencode"
}
