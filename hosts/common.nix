# Settings shared by every host. Import this from each host's
# configuration.nix and only keep host-specific stuff there.
{
  pkgs,
  outputs,
  ...
}: {
  # The overlays (including any custom packages added under ../pkgs) must be
  # applied here too: home-manager/common/nixpkgs.nix applies them for
  # home-manager, but the NixOS system-level pkgs is separate.
  nixpkgs.overlays = [
    outputs.overlays.additions
    outputs.overlays.modifications
    outputs.overlays.unstable-packages
  ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable Flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Packages every host gets - CLI basics only. GUI apps belong in
  # desktop.nix instead, so a headless host doesn't get them.
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    fastfetch
    lshw
    pciutils
    btop
  ];
}
