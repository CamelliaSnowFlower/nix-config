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
    # /srv/minecraft-servers/sticker-shop.
    #
    # NOT under /home/gemini: the module hard-codes ProtectHome=true
    # in its systemd hardening for every server, which makes /home
    # invisible to the sandboxed process regardless of file ownership.
    # A dataDir under /home would never actually be reachable by the
    # running server. /srv keeps that hardening intact.
    #
    # Still running as gemini (instead of the module's default
    # "minecraft" system user), so the sticker-shop subfolder still
    # ends up owned by gemini - readable/writable without sudo, same
    # as if it lived in your home dir, just rooted elsewhere.
    #
    # Group is "users", not "gemini" - isNormalUser on NixOS sets a
    # user's primary group to "users" by default, it does NOT create
    # a same-named group the way most distros do. "gemini" the group
    # doesn't exist, which is exactly why this failed (systemd exit
    # 216/GROUP = it couldn't resolve the configured Group=).
    dataDir = "/srv/minecraft-servers";
    user = "gemini";
    group = "users";

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

      # Carried over from the old server's whitelist.json.
      whitelist = {
        Makizzzzzz = "c456cb89-5462-4540-83e1-44ea076858d9";
        SteveEG = "7e988c95-6335-4633-9ccc-ba13fcdefcc3";
        RoboPuffy = "a3bd4513-ac8f-4335-9d16-51947638c213";
        BustyRustyKat13 = "a14b6b19-4f43-4c74-98a8-e5d1455f1fb2";
        MasterNecro = "5389e106-4bf0-4f93-8a12-1a9d974e7d02";
        VioletSnowFlower = "26b3f155-26db-4976-b3bc-6512b4576e10";
        Violet42269 = "b2319d2c-0767-4752-a7aa-25af49f70de8";
        darknight69240 = "7c566824-53b0-4e1e-860e-84b3a7dba457";
        _Sunet_ = "48405642-5da8-4dd0-9dd7-d3c6811ed87a";
        LegendaryMapache = "2aad2cb9-f886-4063-a171-0585fcad8b11";
        Mat2555 = "03f2d19b-af66-4a13-8a55-1dccd02cf215";
        HieronymusNosk = "bb2be710-ee24-43b5-bc9e-798707d5b64d";
        scrabhalo = "2017f381-2e10-4594-ab37-37087354ce5c";
        HilarioLikeAgua = "d41d15a6-2f99-4cc2-af17-6c8d57e19eaa";
        ransomisbored = "3f2ac61e-507b-4a15-b69c-0fe9eb46bd5d";
        Minerguy0606 = "6fc89472-da53-4142-a66b-da975b4c6afa";
      };
    };
  };

  # The module only pulls in tmux for its own internal use (running
  # each server's console inside a session) - it doesn't put the
  # binary on anyone's interactive PATH. Needed so you can actually
  # attach: `tmux -S /run/minecraft/sticker-shop.sock attach`.
  environment.systemPackages = [ pkgs.tmux ];
}

