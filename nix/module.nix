self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-desktop;
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
  qemu = "${pkgs.qemu_kvm}/bin/qemu-system-${if isAarch64 then "aarch64" else "x86_64"}";
  # Cowork only looks for QEMU parts at Debian paths, so point those at the store.
  coworkLinks =
    {
      "/usr/bin/virtiofsd" = "${pkgs.virtiofsd}/bin/virtiofsd";
    }
    // (
      if isAarch64 then
        {
          "/usr/bin/qemu-system-aarch64" = qemu;
          "/usr/share/AAVMF/AAVMF_CODE.fd" = "${pkgs.OVMF.fd}/FV/AAVMF_CODE.fd";
        }
      else
        {
          "/usr/bin/qemu-system-x86_64" = qemu;
          "/usr/share/OVMF/OVMF_CODE.fd" = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
        }
    );
in
{
  options.programs.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
      defaultText = lib.literalExpression "claude-desktop-linux.packages.\${system}.claude-desktop";
      description = "The Claude Desktop package to install.";
    };

    cowork.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install QEMU, UEFI firmware and virtiofsd, link them where Cowork
        expects them (/usr/bin, /usr/share/OVMF) and load vhost_vsock.
        Users also need to be in the `kvm` group.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals cfg.cowork.enable [
      pkgs.qemu_kvm
      pkgs.virtiofsd
    ];

    boot.kernelModules = lib.optionals cfg.cowork.enable [ "vhost_vsock" ];

    systemd.tmpfiles.rules = lib.optionals cfg.cowork.enable (
      lib.mapAttrsToList (path: target: "L+ ${path} - - - - ${target}") coworkLinks
    );

    # Somewhere to keep the sign-in.
    services.gnome.gnome-keyring.enable = lib.mkDefault true;

    # Claude Code inside the app runs prebuilt Linux binaries.
    programs.nix-ld.enable = lib.mkDefault true;
  };
}
