# The six bulk 2TB drives, as one RAIDZ2 pool - survives any two
# drives failing at once. ~8TB usable (4 drives' worth of capacity,
# 2 drives' worth spent on parity).
#
# Deliberately kept out of disko.nix (the boot drive) and out of
# configuration.nix's disko-related imports for the provisioning step
# specifically - this file gets handed to disko standalone, by path,
# so there's no way the one-time format/mount run can reach the
# already-installed boot drive.
{
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
        datasets = {
          data = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
