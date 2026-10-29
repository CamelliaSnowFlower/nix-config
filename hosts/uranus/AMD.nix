{pkgs, ...}: {
  boot.initrd.kernelModules = ["amdgpu"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = ["amdgpu"];

  # blender-hip was removed from nixpkgs; this re-instantiates nixpkgs
  # with rocmSupport on just to build blender's HIP/ROCm-accelerated
  # variant, instead of flipping the flag for the whole system closure.
  nixpkgs.overlays = [
    (final: prev: {
      blender =
        (import prev.path {
          inherit (prev) system;
          config = prev.config // {rocmSupport = true;};
        })
        .blender;
    })
  ];
}
