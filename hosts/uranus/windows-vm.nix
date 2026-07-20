# Infrastructure for a GPU-passthrough Windows VM, using the GTX 1050
# Ti as a dedicated second GPU. The AMD GPU (see ./AMD.nix) stays with
# the host as normal - only the Nvidia card gets isolated for the VM.
#
# This file gets you the host-side plumbing (IOMMU, isolating the
# card, libvirtd). The VM itself still needs to be created once
# through virt-manager.
#
# --- Before rebuilding ---
# Fill in the placeholder PCI IDs below. Find them with:
#   lspci -nn | grep -i nvidia
# You'll get two lines for the 1050 Ti - the VGA controller and its
# HDMI audio function. Copy both "vendor:device" IDs (the bit in
# square brackets, e.g. 10de:1c82) into the vfio-pci.ids list.
#
# --- After rebuilding and rebooting ---
# 1. Confirm the card is bound to vfio-pci, not nouveau:
#      lspci -nnk -d 10de:
#    "Kernel driver in use: vfio-pci" is what you want to see.
#
# 2. Confirm the 1050 Ti sits in its own clean IOMMU group (no other
#    unrelated devices mixed in), otherwise passthrough will fail:
#      for g in /sys/kernel/iommu_groups/*; do
#        echo "group ${g##*/}:"; lspci -nns $(basename -a $g/devices/*)
#      done | grep -i -B1 nvidia
#
# 3. Open virt-manager, create a new VM:
#    - Point it at a Windows 11 ISO.
#    - Firmware: UEFI (OVMF) - the New VM wizard should offer this
#      once ovmf.enable is on.
#    - Once created: VM details -> Add Hardware -> PCI Host Device,
#      add both the 1050 Ti's VGA function AND its audio function.
#    - Remove the emulated "Video QXL/Virtio" device so Windows uses
#      the passed-through GPU as primary once drivers are installed.
#    - Install VirtIO drivers (pkgs.virtio-win, if you want it added
#      to your config) inside Windows for disk/network performance,
#      then install the real Nvidia driver.
{pkgs, ...}: {
  # Intel CPU (per hardware-configuration.nix), so intel_iommu - not
  # amd_iommu, which is for AMD CPUs and unrelated to the AMD *GPU*
  # here.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];

  # REQUIRED: replace XXXX:XXXX,XXXX:XXXX with the two IDs from the
  # lspci command described above.
  boot.extraModprobeConfig = ''
    options vfio-pci ids=10de:1c82,10de:0fb9
  '';

  # Make sure vfio-pci claims the card before nouveau ever gets a
  # chance to.
  boot.initrd.kernelModules = ["vfio_pci" "vfio" "vfio_iommu_type1"];
  boot.blacklistedKernelModules = ["nouveau" "nvidia"];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      # UEFI firmware - needed for GPU passthrough to work reliably,
      # and required for Windows 11 regardless.
      ovmf.enable = true;
      # Emulated TPM 2.0, which Windows 11 checks for at install time.
      swtpm.enable = true;
    };
  };

  # GUI for creating and managing the VM.
  programs.virt-manager.enable = true;

  users.users.aquarius.extraGroups = ["libvirtd"];
}
