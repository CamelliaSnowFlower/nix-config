# Dataset creation/management for the storage pool. Unlike plain
# disko's own dataset schema (storage-pool.nix), disko-zfs actually
# runs `zfs create`/`zfs set` for these during an ordinary
# `nixos-rebuild switch` - that's the whole reason it exists, and why
# these moved here instead of staying under disko.devices.
#
# Before a real switch, preview exactly what it's about to do:
#   sudo nixos-rebuild --flake .#mercury --sudo dry-activate
{
  disko.zfs = {
    enable = true;
    settings = {
      datasets = {
        # 1. 2D Vector Designs (.svg, templates, text layouts)
        "storage/shop-designs" = {
          properties = {
            mountpoint = "/mnt/storage/shop-designs";
            compression = "zstd";
            recordsize = "128k";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # 2. Large Raw Images (.png, background textures, rasters)
        "storage/shop-assets" = {
          properties = {
            mountpoint = "/mnt/storage/shop-assets";
            compression = "lz4";
            recordsize = "1M";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # 3. 3D Print Meshes (.stl, .3mf, and slicer profiles)
        "storage/shop-3d" = {
          properties = {
            mountpoint = "/mnt/storage/shop-3d";
            compression = "zstd";
            recordsize = "512k";
            "com.sun:auto-snapshot" = "false";
          };
        };

        # 4. Shop Accounting (Invoices, taxes, spreadsheets, PDFs)
        "storage/shop-accounting" = {
          properties = {
            mountpoint = "/mnt/storage/shop-accounting";
            compression = "zstd"; # Drastically shrinks text/spreadsheet files
            recordsize = "128k"; # Standard responsive file access layout
            "com.sun:auto-snapshot" = "true";
          };
        };

        # 5. Shop Videos (vlogs and other video content)
        "storage/shop-videos" = {
          properties = {
            mountpoint = "/mnt/storage/shop-videos";
            # Video is already compressed (h264/h265/etc), so zstd
            # would just burn CPU for little to no space savings -
            # lz4 is cheap and still catches any incompressible-data
            # edge cases. Large recordsize matches the big sequential
            # reads/writes of video files, same as shop-assets.
            compression = "lz4";
            recordsize = "1M";
            # Bulky and easy to re-export/re-upload if lost - skip
            # snapshotting the space, same call as shop-3d.
            "com.sun:auto-snapshot" = "false";
          };
        };

        # 6. Minecraft server backups (not exposed over Samba)
        "storage/minecraft-backups" = {
          properties = {
            mountpoint = "/mnt/storage/minecraft-backups";
            # World saves aren't pre-compressed like video/images, so
            # zstd earns its keep here.
            compression = "zstd";
            recordsize = "128k";
            # The backup script itself keeps a rolling window of past
            # backups (see minecraft-backup.nix) - ZFS snapshotting on
            # top of that would just be redundant versioning.
            "com.sun:auto-snapshot" = "false";
          };
        };
      };
    };
  };
}
