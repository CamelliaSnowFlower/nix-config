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
    filetree.neo-tree.enable = true;
    tabline.nvimBufferline.enable = true;
    
    binds = {
     whichKey.enable = true;
     cheatsheet.enable = true;
    };

    languages = {
     enableLSP = true;
     enableTreesitter = true;
     enableFormat = true;

     nix.enable = true;
     markdown.enable = true;
    };
   };
  };
 };
}
