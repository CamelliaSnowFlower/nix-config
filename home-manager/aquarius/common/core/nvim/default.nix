{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    inputs.nvf.homeManagerModules.default
    ./nvimTree.nix
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

        spellcheck.enable = true;
        spellcheck.extraSpellWords = {"en.utf-8" = ["Astro"];};
        # mini text editing
        mini.ai.enable = true;
        mini.comment.enable = true;
        mini.completion.enable = true;
        mini.operators.enable = true;
        mini.surround.enable = true;
        #mini general workflow
        mini.basics.enable = true;
        mini.bracketed.enable = true;
        #mini appearance
        mini.icons.enable = true;
        mini.statusline.enable = true;
        mini.tabline.enable = true;
        mini.starter.enable = true;

        mini.starter.setupOpts = {
          header = "Lets Code AJ";
          footer = lib.generators.mkLuaInline ''
            os.date()
          '';
        };

        telescope.enable = true;
        tabline.nvimBufferline.enable = true;
        autocomplete.nvim-cmp.enable = true;

        binds = {
          whichKey.enable = true;
          cheatsheet.enable = true;
        };

        lsp.enable = true;
        languages = {
          enableTreesitter = true;
          enableFormat = true;

          nix.enable = true;
          markdown.enable = true;
          astro.enable = true;
          python.enable = true;
          rust = {
            enable = true;
            crates.enable = true;
          };
        };

        presence.neocord.enable = true;
        terminal = {
          toggleterm = {
            enable = true;
            lazygit.enable = true;
          };
        };
      };
    };
  };
}
