{config, ...}: {
  
  programs.nvf.settings.vim.filetree.nvimTree = {
    enable = true;
    setupOpts = {
      actions ={
        open_file.quit_on_open = true;
      };
      diagnostics = {
        enable = true;
      };
      filters = {
        dotfiles = true;
        exclude = [];
        git_clean = false;
        git_ignored = false;
        no_buffer = false;
      };
      git.enable = true;
      hijack_cursor = true;
      modified = {
        enable = true;
      };
      view = {
        float = {
          enable = true;
          # open_win_config ={};
        };
        preserve_window_proportions = false;
        relativenumber = true;
        signcolumn = "no";
        width = {
          min = 30;
          max = -1;
          padding = 1;
        };
      };
    };
  };
}
