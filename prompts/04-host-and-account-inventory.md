# Prompt 4 — Consolidate Host and Account Inventory

Design a modest, typed pattern for the host and account inventory without obscuring the NixOS module graph. Review `flake.nix`, user declarations on Saturn/Uranus/Mercury, repeated groups/descriptions, and Home Manager outputs.

The goal is to prevent drift when adding users/hosts, not to create a framework for its own sake. Keep hardware, disk, network, firewall, and privilege choices visible in the relevant host module. Make architecture explicit where needed instead of assuming `x86_64-linux` invisibly. Preserve current users, groups, profiles, outputs, and privileges exactly unless separately approved.

Deliver a before/after model and a minimal patch. Prove that every current output/account is preserved. Evaluate every host and Home Manager output. Explicitly verify no one accidentally gains `wheel`, SSH access, Samba access, or broad group membership.
