{
  config,
  pkgs,
  ...
}: {
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

      # Empty to start - add usernames/UUIDs here (or manage live with
      # `whitelist add <name>` in the server console) since
      # white-list = true above locks it down until you do.
      whitelist = {};
    };
  };
  enviroment.systemPackages = [pkgs.tmux];
}
