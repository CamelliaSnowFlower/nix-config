{config, lib, pkgs, ... }:
{ 
 # Home-manager Script
 home.packages = with pkgs; [
  (writeShellScriptBin  "hms" ''home-manager switch --flake .#aquarius@saturn'' )
 ];
 #TODO need to make more scripts for automating git and/or look into lazy git
}
