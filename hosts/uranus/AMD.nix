{ pkgs, ... }:
{

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  
  services.xserver.videoDrivers = [ "amdgpu" ];

  # blender-hip was removed from nixpkgs; this is what now gets you the
  # equivalent HIP/ROCm-accelerated build of blender (and any other
  # ROCm-aware package) instead.
  nixpkgs.config.rocmSupport = true;
}
