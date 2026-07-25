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
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };

      # 3. Network Share for GIMP assets and heavy images
      "Shop-Assets" = {
        "path" = "/mnt/storage/shop-assets";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };

      # 4. Network Share for STL/3MF 3D print models
      "Shop-3DModels" = {
        "path" = "/mnt/storage/shop-3dmodels";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force group" = "users";
      };
    };
  };

  # 2. Enable WSDD to make the NAS automatically show up in Windows Network Explorer
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}

