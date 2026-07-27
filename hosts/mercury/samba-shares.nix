# samba-shares.nix
{ config, pkgs, ... }: {

  # 1. Enable the Samba service
  services.samba = {
    enable = true;
    openFirewall = true; # Automatically opens network ports 139 and 445

    # Core global settings for security and performance
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "Sticker Shop NAS";
        "netbios name" = "shopnas";
        "security" = "user";
        
        # Security: Prevent anonymous guest access to your business files
        "invalid users" = [ "root" ];
        "guest account" = "nobody";
        "map to guest" = "Bad User";

        # Performance tuning for fast file transfers over the network
        "aio read size" = "1";
        "aio write size" = "1";
        "strict locking" = "no";
        "use sendfile" = "yes";
      };

      # 2. Network Share for Inkscape vector templates
      "Shop-Designs" = {
        "path" = "/mnt/storage/shop-designs";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        # 0644/0755 only gave the uploading owner write access; the
        # shared 'users' group could read but not edit. Bumped to
        # give the group write too, and "force *" enforces it
        # regardless of each client's umask.
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "users";
      };

      # 3. Network Share for GIMP assets and heavy images
      "Shop-Assets" = {
        "path" = "/mnt/storage/shop-assets";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "users";
      };

      # 4. Network Share for STL/3MF 3D print models
      "Shop-3DModels" = {
        "path" = "/mnt/storage/shop-3d"; 
        # Fixed to match your ZFS dataset path
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "users";
      };

      # 5. Network Share for vlogs and other video content
      "Shop-Videos" = {
        "path" = "/mnt/storage/shop-videos";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "users";
      };

      # NEW: 6. Network Share for accounting, spreadsheets, and business receipts
      "Shop-Accounting" = {
        "path" = "/mnt/storage/shop-accounting";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";    # Restricts file access purely to the creator
        "directory mask" = "0700"; # Restricts folder exploration for privacy
        "force group" = "users";
      };
    };
  };

  # 2. Enable WSDD to make the NAS automatically show up in Windows Network Explorer
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # 3. Fix dataset mountpoint ownership/permissions on every boot.
  #
  # disko-zfs creates new datasets as root:root 0755 - Samba's "force
  # group"/"force create mode"/"force directory mode" only apply to
  # files and folders Samba itself creates *inside* a share, never
  # retroactively to the share's own root directory. Without this,
  # any collaborative share (new or freshly recreated) starts out
  # unwritable by gubby/aquarius even though everything created
  # underneath it would inherit the right permissions.
  #
  # 2775 = group-writable + setgid, so anything created directly at
  # the dataset root also inherits the "users" group.
  systemd.tmpfiles.rules = [
    "z /mnt/storage/shop-designs 2775 root users - -"
    "z /mnt/storage/shop-assets 2775 root users - -"
    "z /mnt/storage/shop-3d 2775 root users - -"
    "z /mnt/storage/shop-videos 2775 root users - -"
    # Shop-Accounting deliberately excluded - stays root-owned/private.
  ];

  # tmpfiles normally runs early in boot, before the ZFS pool is
  # mounted - without this ordering it'd either fail (path doesn't
  # exist yet) or silently set permissions on a directory that gets
  # unmounted-over a moment later. Run it only after zfs-mount.service
  # (enabled in configuration.nix) has done its job.
  systemd.services.systemd-tmpfiles-setup = {
    after = [ "zfs-mount.service" ];
    wants = [ "zfs-mount.service" ];
  };
}

