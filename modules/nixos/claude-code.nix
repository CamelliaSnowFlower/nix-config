# claude-code.nix
#
# Installs Anthropic's Claude Code CLI (`claude`) system-wide.
# Enable per host with:  programs.claude-code.enable = true;
#
# No unfree allowance here: hosts/common.nix already sets
# nixpkgs.config.allowUnfree = true for every host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.claude-code;
in {
  options.programs.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.claude-code;
      defaultText = lib.literalExpression "pkgs.claude-code";
      description = "The Claude Code package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # The Nix store is read-only, so Claude Code's built-in self-updater
    # can't work. Updates come from `nix flake update` instead.
    environment.sessionVariables.DISABLE_AUTOUPDATER = "1";
  };
}
