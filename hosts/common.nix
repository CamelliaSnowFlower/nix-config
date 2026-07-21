# Settings shared by every host. Import this from each host's
# configuration.nix and only keep host-specific stuff there.
{
  pkgs,
  outputs,
  ...
}: {
  # Without this, custom packages from ../pkgs (like deepnest) are only
  # visible to home-manager, not to environment.systemPackages here -
  # home-manager/aquarius/default.nix applies these same overlays on
  # its own, but the NixOS system-level pkgs needs them applied too.
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
