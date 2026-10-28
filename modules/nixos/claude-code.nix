# modules/claude-code.nix
#
# Installs Anthropic's Claude Code CLI (`claude`) system-wide.
# Enable per host with:  modules.claude-code.enable = true;
{ config, lib, pkgs, ... }:

let
  cfg = config.modules.claude-code;
in
{
  options.modules.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      defaultText = lib.literalExpression "pkgs.claude-code";
      description = "The Claude Code package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Claude Code is unfree. If you already set
    # `nixpkgs.config.allowUnfree = true` or define your own
    # allowUnfreePredicate elsewhere, delete this block to avoid a conflict.
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "claude-code" ];

    environment.systemPackages = [ cfg.package ];

    # The Nix store is read-only, so Claude Code's built-in self-updater
    # can't work. Turn it off; updates come from `nix flake update` instead.
    environment.sessionVariables.DISABLE_AUTOUPDATER = "1";
  };
}
