{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    gnomeExtensions.blur-my-shell
  ];
}
