{ pkgs, ... }:
{

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  
  services.xserver.videoDrivers = [ "amdgpu" ];
}
