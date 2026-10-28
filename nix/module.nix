self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-desktop;
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
        Install QEMU and virtiofsd and load vhost_vsock for Cowork.
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

    # Somewhere to keep the sign-in.
    services.gnome.gnome-keyring.enable = lib.mkDefault true;

    # Claude Code inside the app runs prebuilt Linux binaries.
    programs.nix-ld.enable = lib.mkDefault true;
  };
}
