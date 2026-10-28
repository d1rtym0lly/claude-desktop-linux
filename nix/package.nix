# Claude Desktop for NixOS: the official Debian build, patched for the Nix store.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libcap_ng,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libseccomp,
  libsecret,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  vulkan-loader,
  xdg-utils,
  xorg,
  # nixpkgs 26.05+ names; older releases fall back to the xorg set.
  libx11 ? xorg.libX11,
  libxcomposite ? xorg.libXcomposite,
  libxdamage ? xorg.libXdamage,
  libxext ? xorg.libXext,
  libxfixes ? xorg.libXfixes,
  libxrandr ? xorg.libXrandr,
  libxcb ? xorg.libxcb,
  libxshmfence ? xorg.libxshmfence,
}:

let
  sources = lib.importJSON ../sources.json;
  debArch =
    {
      x86_64-linux = "amd64";
      aarch64-linux = "arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}");
  src = sources.${debArch};

  # Loaded with dlopen at runtime, so autoPatchelf can't see them.
  runtimeLibs = [
    libGL
    libnotify
    libpulseaudio
    libsecret
    systemd
    vulkan-loader
  ];
in
stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit (sources) version;

  src = fetchurl { inherit (src) url sha256; };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng
    libdrm
    libgbm
    libseccomp
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxshmfence
  ]
  ++ runtimeLibs;

  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir root
    dpkg-deb --fsys-tarfile "$src" | tar -x -C root --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    [ -d root/usr ] && cp -r root/usr/. $out/
    [ -d root/opt ] && cp -r root/opt $out/opt
    rm -rf $out/share/keyrings

    # Find what the official /usr/bin/claude-desktop points at, inside $out.
    official=$out/bin/claude-desktop
    if [ -L "$official" ]; then
      app=$(readlink "$official")
      case "$app" in
        /usr/*) app=$out/''${app#/usr/} ;;
        /opt/*) app=$out$app ;;
        /*) echo "unexpected launcher target: $app" >&2; exit 1 ;;
        *) app=$(realpath -m -s "$out/bin/$app") ;;
      esac
      rm "$official"
    elif [ -f "$official" ]; then
      app=$out/libexec/claude-desktop/claude-desktop-official
      install -Dm755 "$official" "$app"
      rm "$official"
      # A shell launcher may refer to the Debian install paths.
      if head -c 2 "$app" | grep -q '#!'; then
        sed -i -e "s|/usr/lib/|$out/lib/|g" -e "s|/usr/share/|$out/share/|g" -e "s|/opt/|$out/opt/|g" "$app"
      fi
    else
      echo "the .deb has no /usr/bin/claude-desktop; its layout changed" >&2
      exit 1
    fi

    # Without setuid (impossible in the store) Chromium uses user namespaces.
    find $out -name chrome-sandbox -delete

    sed "s|@APP@|$app|" ${../common/claude-desktop-launcher.sh} > $out/bin/claude-desktop
    chmod +x $out/bin/claude-desktop
    install -Dm755 ${../common/claude-desktop-autostart.sh} $out/bin/claude-desktop-autostart

    for entry in $out/share/applications/*.desktop; do
      [ -f "$entry" ] || continue
      sed -i -E 's|^(Exec=)[^ ]*claude[^ ]*|\1claude-desktop|; s|^(TryExec=).*|\1claude-desktop|' "$entry"
    done

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
  '';

  meta = {
    description = "Claude Desktop: Chat, Cowork and Claude Code (official Anthropic app)";
    homepage = "https://claude.ai/download";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "claude-desktop";
  };
}
