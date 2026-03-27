{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.librewolf = {
    enable = true;
    profiles = {
      aquarius = {
        id = 0;
        name = "aquarius";
        isDefault = true;
        #settings = {};
        extensions = with pkgs.nur.repos.rycee.firefox-addons; [
         darkreader
         ];
        };
      };
    };
}
