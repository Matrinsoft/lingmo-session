rootdir := ''
prefix := '/usr'
cargo-target-dir := env('CARGO_TARGET_DIR', 'target')
orca := '/usr/bin/orca'
lingmo_dconf_profile := prefix + '/share/dconf/profile/lingmo'
usrdir := absolute_path(clean(rootdir / prefix))
bindir := usrdir / 'bin'
systemddir := usrdir / 'lib' / 'systemd' / 'user'
sessiondir := usrdir / 'share' / 'wayland-sessions'
applicationdir := usrdir / 'share' / 'applications'

default: build-release

build-debug *args:
    ORCA={{ orca }} cargo build {{ args }}

# Compile with release profile
build-release *args: (build-debug '--release' args)

# Compile with a vendored tarball
build-vendored *args:
    @just vendor-extract
    cargo build --release {{ args }} --frozen --offline

# Remove Cargo build artifacts
clean:
    cargo clean

# Also remove .cargo and vendored dependencies
clean-dist: clean
    rm -rf .cargo vendor vendor.tar target

# Installs files into the system
install:
    echo {{ lingmo_dconf_profile }}
    # main binary
    install -Dm0755 {{ cargo-target-dir }}/release/lingmo-session {{ bindir }}/lingmo-session

    # session start script
    install -Dm0755 data/start-lingmo {{ bindir }}/start-lingmo
    sed -i "s|DCONF_PROFILE=lingmo|DCONF_PROFILE={{ lingmo_dconf_profile }}|" {{ bindir }}/start-lingmo

    # systemd target
    install -Dm0644 data/lingmo-session.target {{ systemddir }}/lingmo-session.target

    # session
    install -Dm0644 data/lingmo.desktop {{ sessiondir }}/lingmo.desktop

    # mimeapps
    install -Dm0644 data/lingmo-mimeapps.list {{ applicationdir }}/lingmo-mimeapps.list

    # dconf profile
    install -Dm644 data/dconf/profile/lingmo {{ rootdir }}/{{ lingmo_dconf_profile }}

# Vendor Cargo dependencies locally
vendor:
	mkdir -p .cargo
	cargo vendor 2>/dev/null | awk '/^\[/{p=1} p' > .cargo/config.toml
	if ! grep -q 'directory' .cargo/config.toml 2>/dev/null; then
	echo '[source.crates-io]' >> .cargo/config.toml
	echo 'replace-with = "vendored-sources"' >> .cargo/config.toml
	echo '' >> .cargo/config.toml
	echo '[source.vendored-sources]' >> .cargo/config.toml
	echo 'directory = "vendor"' >> .cargo/config.toml
	fi
	grep '^source = "git+" Cargo.lock | sed 's/source = "//;s/"$//' | sort -u | while read src; do \
	echo "[source \"$src\"]"; \
	echo 'replace-with = "vendored-sources"'; \
	echo ""; \
	done >> .cargo/config.toml
	tar pcf vendor.tar vendor .cargo/config.toml
	rm -rf vendor

# Extracts vendored dependencies
[private]
vendor-extract:
    rm -rf vendor
    tar pxf vendor.tar

# Bump cargo version, create git commit, and create tag
tag version:
    find -type f -name Cargo.toml -exec sed -i '0,/^version/s/^version.*/version = "{{ version }}"/' '{}' \; -exec git add '{}' \;
    cargo check
    cargo clean
    git add Cargo.lock
    git commit -m 'release: {{ version }}'
    git commit --amend
    git tag -a {{ version }} -m ''
