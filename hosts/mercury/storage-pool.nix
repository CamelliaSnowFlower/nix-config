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
          # 1. 2D Vector Designs (.svg, templates, text layouts)
          "shop-designs" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-designs";
            options = {
              compression = "zstd";
              recordsize = "128k";
              "com.sun:auto-snapshot" = "true"; # Highly recommended to back these up
            };
          };

          # 2. Large Raw Images (.png, background textures, rasters)
          "shop-assets" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-assets";
            options = {
              compression = "lz4"; 
              recordsize = "1M"; # Optimizes hard drives for fast image loading
              "com.sun:auto-snapshot" = "true";
            };
          };

          # 3. 3D Print Meshes (.stl, .3mf, and slicer profiles)
          "shop-3d" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-3d";
            options = {
              compression = "zstd"; # Squeezes down massive uncompressed STL files
              recordsize = "512k";  # Clean sweet-spot for 3D model streams
              "com.sun:auto-snapshot" = "false"; # Lower priority for snapshots
          };
        };
      };
    };
  };
}
