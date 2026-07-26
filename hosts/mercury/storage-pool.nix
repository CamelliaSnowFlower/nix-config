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
        datasets = {
          # 1. 2D Vector Designs (.svg, templates, text layouts)
          "shop-designs" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-designs";
            options = {
              compression = "zstd";
              recordsize = "128k";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # 2. Large Raw Images (.png, background textures, rasters)
          "shop-assets" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-assets";
            options = {
              compression = "lz4"; 
              recordsize = "1M";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # 3. 3D Print Meshes (.stl, .3mf, and slicer profiles)
          "shop-3d" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-3d";
            options = {
              compression = "zstd";
              recordsize = "512k";
              "com.sun:auto-snapshot" = "false";
            };
          };

          # NEW: 4. Shop Accounting (Invoices, taxes, spreadsheets, PDFs)
          "shop-accounting" = {
            type = "zfs_fs";
            mountpoint = "/mnt/storage/shop-accounting";
            options = {
              compression = "zstd"; # Drastically shrinks text/spreadsheet files
              recordsize = "128k";  # Standard responsive file access layout
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
    };
  };

  # Automated ZFS Snapshot Policy via Sanoid
  services.sanoid = {
    enable = true;
    
    templates = {
      # Heavy protection for active artwork templates and business data
      production-critical = {
        hourly = 24;      # Keep every hour for the last 1 day
        daily = 14;       # Keep every day for the last 2 weeks
        monthly = 3;      # Keep every month for the last quarter
        autoprune = true;
        autosnap = true;
      };
      
      # Lighter rules for bulky 3D models to save disk space
      bulky-assets = {
        hourly = 0;       # Skip hourly captures
        daily = 7;        # Keep daily versions for 1 week
        monthly = 1;      # Keep 1 monthly fallback
        autoprune = true;
        autosnap = true;
      };
    };

    # Apply the policies directly to your ZFS datasets
    datasets = {
      "storage/shop-designs"    = { useTemplate = [ "production-critical" ]; };
      "storage/shop-assets"     = { useTemplate = [ "production-critical" ]; };
      "storage/shop-accounting" = { useTemplate = [ "production-critical" ]; }; # Protected
      "storage/shop-3d"         = { useTemplate = [ "bulky-assets" ]; };
    };
  };
}

