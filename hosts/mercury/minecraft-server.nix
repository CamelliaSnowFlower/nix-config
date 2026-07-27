# minecraft-server.nix
#
# Vanilla Minecraft 26.2 ("Chaos Cubed") server via nix-minecraft.
# The module/overlay itself are wired up at the flake level (see
# flake.nix's mercury nixosSystem) since they need to attach before
# this file's pkgs.minecraftServers reference resolves.
{ config, pkgs, ... }: {
  services.minecraft-servers = {
    enable = true;

    # Required to run a Minecraft server at all - by setting this you
    # are accepting Mojang's EULA (https://aka.ms/MinecraftEULA).
    eula = true;

    # Puts each server's files at ${dataDir}/<name> - here, that's
    # /home/gemini/minecraft-servers/sticker-shop. Running the service
    # as gemini (instead of the module's default "minecraft" system
    # user) means that folder is just a normal part of your home dir:
    # readable/writable without touching permissions, so you can drop
    # your old world in and upgrade it yourself.
    dataDir = "/home/gemini/minecraft-servers";
    user = "gemini";
    group = "gemini";

    servers.sticker-shop = {
      enable = true;
      openFirewall = true;
      # NOTE: verify this attribute name once you've pulled the flake
      # input - nix-minecraft names vanilla packages "vanilla-<version>"
      # with periods swapped for underscores, so 26.2 should land at
      # vanilla-26_2, but confirm before deploying:
      #   nix eval .#nixosConfigurations.mercury.pkgs.minecraftServers --apply builtins.attrNames
      # or just tab-complete in `nix repl`. If it's not there yet,
      # bump the input with `nix flake lock --update-input nix-minecraft`.
      package = pkgs.minecraftServers.vanilla-26_2;

      # RAM limit: 6GB heap, min == max so the JVM claims it all
      # upfront rather than growing/shrinking during play.
      jvmOpts = "-Xms6G -Xmx6G";

      serverProperties = {
        server-port = 25565;
        difficulty = "normal";
        gamemode = "survival";
        max-players = 10;
        motd = "Sticker Shop NAS - Vlog & Hangout Server";
        white-list = true;
      };

      # Empty to start - add usernames/UUIDs here (or manage live with
      # `whitelist add <name>` in the server console) since
      # white-list = true above locks it down until you do.
      whitelist = {};
    };
  };
}

