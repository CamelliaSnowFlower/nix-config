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
    ./disko.nix
    ./storage-pool.nix
  ];

  networking.hostName = "mercury"; # Define your hostname.

  # ZFS support for the storage-pool.nix RAIDZ2 pool. hostId just
  # needs to be unique among any ZFS hosts on the same network - not
  # secret, doesn't need to match anything.
  boot.supportedFilesystems = ["zfs"];
  networking.hostId = "6d778fb4";
  # Not the root pool, so it needs to be told to import at boot -
  # otherwise /mnt/storage would come up empty until you `zpool
  # import` it by hand.
  boot.zfs.extraPools = ["storage"];

  # aquarius's key from uranus - lets you SSH in from uranus without a
  # password, and means root access survives a reinstall without
  # needing the USB-recovery dance again.
  users.users.gemini.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJmwLjawHnMhm7IT+6PegvciSDAmEtinztsMYhhw7uyB camelliasnowflower@gmail.com"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJmwLjawHnMhm7IT+6PegvciSDAmEtinztsMYhhw7uyB camelliasnowflower@gmail.com"
  ];

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
