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
# 2. Re-run the IOMMU group check - confirm the 1050 Ti (and its audio
#    function) now sit in their own group, separate from the AMD GPU
#    and the PCIe switch bridges. If they're still merged, the
#    override isn't taking effect and needs troubleshooting before
#    going further:
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
# --- Why the XanMod kernel ---
# Your Z370 board groups both GPUs (and the PCIe switch they sit
# behind) into one IOMMU group instead of isolating them - common on
# consumer boards that don't expose ACS. XanMod is a normal
# general-purpose kernel that happens to ship the PCIe ACS override
# patch built in, which avoids needing to fetch and hope an external
# out-of-tree patch still applies cleanly to whatever kernel version
# is current. It's a full from-source kernel build the first time,
# so expect that rebuild to take a while.
{pkgs, ...}: {
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

  # Intel CPU (per hardware-configuration.nix), so intel_iommu - not
  # amd_iommu, which is for AMD CPUs and unrelated to the AMD *GPU*
  # here. pcie_acs_override is what actually splits the merged IOMMU
  # group - "downstream" covers the PCIe switch, "multifunction"
  # covers each GPU's own VGA+audio pairing.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
    "pcie_acs_override=downstream,multifunction"
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
      # Emulated TPM 2.0, which Windows 11 checks for at install time.
      # (UEFI/OVMF firmware used to need enabling here too, but as of
      # recent nixpkgs it ships with QEMU by default - nothing to set.)
      swtpm.enable = true;
    };
  };

  # GUI for creating and managing the VM.
  programs.virt-manager.enable = true;

  users.users.aquarius.extraGroups = ["libvirtd"];
}
