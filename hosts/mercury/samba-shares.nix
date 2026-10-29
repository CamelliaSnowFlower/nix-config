# samba-shares.nix
{
  config,
  pkgs,
  ...
}: let
  # The business-side accounts, as opposed to the artists group below.
  # Explicit "valid users" on every share closes a gap: without it, any
  # valid Samba account - including the new artist accounts added for
  # Shop-Inbox - would be able to browse every other share too,
  # Shop-Accounting included. Listing the current accounts here changes
  # nothing for aquarius/gubby; it only stops future accounts (artists)
  # from inheriting access they were never meant to have.
  adminUsers = ["aquarius" "gubby"];
  # Artists only need Shop-Inbox, so they're added there and nowhere else.
  inboxUsers = adminUsers ++ ["@artists"];

  # Shop-Inbox is reachable from the LAN (admins pulling at home) and from
  # the tailnet (artists, and admins pulling remotely) - 100.64.0.0/10 is
  # Tailscale's standard CGNAT range; confirm with `tailscale ip -4` on
  # mercury once it's joined the tailnet. Anything else (e.g. a future
  # port-forward) is denied at the Samba layer as defense in depth on top
  # of the Tailscale ACL restricting artist devices to mercury:445 only
  # (see tailscale.nix) - mercury isn't port-forwarded today, so this
  # mainly guards against that changing by accident later.
  inboxHostsAllow = ["192.168.1.0/24" "100.64.0.0/10" "127.0.0.1"];
in {
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
        "invalid users" = ["root"];
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
        "valid users" = adminUsers;
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
        "valid users" = adminUsers;
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
        "valid users" = adminUsers;
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
        "valid users" = adminUsers;
      };

      # NEW: 6. Network Share for accounting, spreadsheets, and business receipts
      "Shop-Accounting" = {
        "path" = "/mnt/storage/shop-accounting";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600"; # Restricts file access purely to the creator
        "directory mask" = "0700"; # Restricts folder exploration for privacy
        "force group" = "users";
        "valid users" = adminUsers;
      };

      # 7. Finished-goods output share. Used to be mirrored one-way to
      # Google Drive by outbox-sync.nix for external pickup; that sync
      # was removed (unreliable on Google's end). The share itself
      # stays - hosts/uranus/sticker-automation.nix still mounts it as
      # the sticker workflow's production output/staging location -
      # and is now reachable by admins directly over Tailscale as well
      # as the LAN, same as every other admin share.
      "Shop-Outbox" = {
        "path" = "/mnt/storage/outbox";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "users";
        "valid users" = adminUsers;
      };

      # 8. Drop-off share for external artists (over Tailscale) and admin
      # pull access. See tailscale.nix for the Tailscale/ACL side and
      # configuration.nix for the artists group/accounts.
      "Shop-Inbox" = {
        "path" = "/mnt/storage/shop-inbox";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "force group" = "artists";
        "valid users" = inboxUsers;
        "hosts allow" = inboxHostsAllow;
        "hosts deny" = ["0.0.0.0/0"];
      };
    };
  };

  # 2. Enable WSDD to make the NAS automatically show up in Windows Network Explorer
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # 3. Ownership and mode of each dataset root are set by
  # storage-permissions.nix (a service ordered after zfs-mount.service),
  # which replaced the old tmpfiles rules. Shop-Accounting is deliberately
  # not managed there and stays root-owned/private.
}
