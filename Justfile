rootdir := ''
prefix := '/usr'
cargo-target-dir := env('CARGO_TARGET_DIR', 'target')
orca := '/usr/bin/orca'
cosmic_dconf_profile := prefix + '/share/dconf/profile/cosmic'
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
    echo {{ cosmic_dconf_profile }}
    # main binary
    install -Dm0755 {{ cargo-target-dir }}/release/cosmic-session {{ bindir }}/cosmic-session

    # session start script
    install -Dm0755 data/start-cosmic {{ bindir }}/start-cosmic
    sed -i "s|DCONF_PROFILE=cosmic|DCONF_PROFILE={{ cosmic_dconf_profile }}|" {{ bindir }}/start-cosmic

    # systemd target
    install -Dm0644 data/cosmic-session.target {{ systemddir }}/cosmic-session.target

    # session
    install -Dm0644 data/cosmic.desktop {{ sessiondir }}/cosmic.desktop

    # mimeapps
    install -Dm0644 data/cosmic-mimeapps.list {{ applicationdir }}/cosmic-mimeapps.list

    # dconf profile
    install -Dm644 data/dconf/profile/cosmic {{ rootdir }}/{{ cosmic_dconf_profile }}

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
