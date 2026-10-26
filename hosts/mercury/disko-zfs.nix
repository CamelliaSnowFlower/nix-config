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
        # 1. Design source files (.svg, templates, plus layered working
        # files: GIMP .xcf, Photoshop .psd/.psb, Illustrator .ai,
        # InDesign .indd, Affinity, Krita, etc.)
        "storage/shop-designs" = {
          properties = {
            mountpoint = "/mnt/storage/shop-designs";
            # Layered project files are large and usually compress
            # well (xcf especially), and small SVG/text files compress
            # very well, so zstd stays the right call here.
            compression = "zstd";
            # Bumped from 128k: layered files are tens to hundreds of
            # MB and get read/written whole. Smaller files just use
            # smaller blocks (recordsize is a ceiling, not a minimum).
            # Not 1M, since this dataset is snapshotted hourly and
            # in-place edits would pin larger blocks in snapshots.
            recordsize = "512k";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # 2. Photos, raster images, and PDFs (.jpg, .heic, .png,
        # textures, reference PDFs)
        "storage/shop-assets" = {
          properties = {
            mountpoint = "/mnt/storage/shop-assets";
            # Mixed content: PNG/PDF can still shrink a bit, JPEG/HEIC
            # won't. Recent OpenZFS aborts zstd early on blocks that
            # turn out to be incompressible, so photos cost almost no
            # extra CPU while PDFs/PNGs still get squeezed. (Was lz4.)
            compression = "zstd";
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

        # 7. Outbox: files staged for sharing outside the network via
        # the rclone -> Google Drive sync (not exposed over Samba).
        # Disposable copy - the originals live in the shop-* datasets.
        "storage/outbox" = {
          properties = {
            mountpoint = "/mnt/storage/outbox";
            # Uncompressed by request. Mixed file types, and anything
            # already compressed would gain nothing anyway.
            compression = "off";
            recordsize = "1M";
            # No snapshots. This dataset is deliberately absent from
            # sanoid.nix as well - sanoid only snapshots datasets
            # listed there.
            "com.sun:auto-snapshot" = "false";
          };
        };
      };
    };
  };
}
