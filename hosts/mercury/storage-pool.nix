{ pkgs, ... }: {

  disko.devices = {
    disk = {
      storage1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A4B8KS8G5W";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
      storage2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A4B8KW35VW";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
      storage3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A4B8KW3E7W";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
      storage4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A4B8KW3HXW";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
      storage5 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A4B8KW3L5W";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
      storage6 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUA722020ALA330_JK11A5BEHH4LSX";
        content = {
          type = "zfs";
          pool = "storage";
        };
      };
    };

    zpool = {
      storage = {
        type = "zpool";
        mode = "raidz2";
        rootFsOptions = {
          compression = "lz4";
          "com.sun:auto-snapshot" = "false";
        };
        # Datasets moved to disko-zfs.nix - plain disko's own dataset
        # declarations only take effect through its one-time
        # destructive CLI run (which already happened, for the pool
        # itself), not through an ordinary `nixos-rebuild switch`.
        # disko-zfs is the piece that actually runs `zfs create` for
        # new datasets during a normal switch.
      };
    };
  };
}

