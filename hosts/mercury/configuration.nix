# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
#
# Headless NAS - no desktop.nix import on purpose, this machine has no
# iGPU and no monitor attached day-to-day.
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Generate this on the real hardware with `nixos-generate-config`
    # before the first build - it doesn't exist yet.
    ./hardware-configuration.nix
    ../common.nix
    # Pool layout goes here once it's written - not yet, since it
    # needs the real /dev/disk/by-id paths from the actual machine.
    # ./disko.nix
  ];

  networking.hostName = "mercury"; # Define your hostname.

  # Define a user account for managing this system.
  users.users.gemini = {
    isNormalUser = true;
    description = "Gemini";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
    ];
  };

  # Headless server - manage this over SSH.
  services.openssh.enable = true;

  # This is a fresh install, so this stays at whatever release you
  # actually install with - see the comment on this option in
  # saturn/uranus's configuration.nix for why it's not bumped later.
  system.stateVersion = "26.05";
}
