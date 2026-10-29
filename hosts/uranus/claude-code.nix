# claude-code.nix
#
# Claude Code on uranus. The module lives in modules/nixos/claude-code.nix
# and is pulled in through the `outputs` specialArg, same as odysseus.nix.
{outputs, ...}: {
  imports = [outputs.nixosModules.claude-code];

  programs.claude-code.enable = true;
}
