{...}: {
  imports = [
    ../options.nix
    ./photography.nix
    ./coding.nix
    ./sysadmin.nix
  ];
  # enable fonts delcared by stylix to be found
  fonts.fontconfig.enable = true;
}
