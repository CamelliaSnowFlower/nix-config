{
  config,
  lib,
  pkgs,
  ...
}: {
  # Nix Scripts
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "Duo" ''gnome-monitor-config set -LM HDMI-1 -m 1920x1080@75.002 -t normal -LpM DP-3 -y 1080 -t normal -m 2560x1440@164.956'')
    (writeShellScriptBin "Gamer" ''gnome-monitor-config set -LpM DP-3 -t normal -m 2560x1440@164.956'')
    (writeShellScriptBin "TV" ''gnome-monitor-config set -LpM HDMI-1 -m 1920x1080@75.002 -t normal'')
     ];
}
