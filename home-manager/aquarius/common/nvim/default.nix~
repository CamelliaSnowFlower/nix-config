{config, inputs, lib, pkgs, ... }:
{
 imports = [
  inputs.nvf.homeManagerModules.default
 ];
 

 programs.nvf = {
  enable = true;
  enableManpages = true;
  settings = {
   vim = {
    vimAlias = true;
    theme = {
     enable = true; 
     name = "gruvbox";
     style = "dark";
    };
   
    statusline.lualine.enable = true;
    telescope.enable = true;
    autocomplete.nvim-cmp.enable = true;

    languages = {
     enableLSP = true;
     enableTreesitter = true;

     nix.enable = true;
    };
   };
  };
 };
}
