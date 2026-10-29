# tailscale.nix
#
# Joins mercury to the tailnet so artists can drop art files into
# Shop-Inbox (see samba-shares.nix) without opening Samba to the public
# internet, and so admins can pull from Shop-Inbox remotely too.
#
# This mirrors the existing `services.tailscale.enable = true;` already
# running on uranus (hosts/uranus/sticker-automation.nix) - same tailnet,
# same minimal module usage, no subnet routing or exit-node features.
#
# =====================================================================
# FIRST-TIME SETUP (manual - not declarative)
# =====================================================================
#
# 1. After switching this config, authenticate mercury to your tailnet:
#        sudo tailscale up
#    Follow the printed login URL. Confirm with:
#        tailscale status
#
# 2. For each artist, in the Tailscale admin console (not this repo):
#      a. Invite them to the tailnet (Settings -> Users -> Invite), or
#         share just the mercury node with them if your plan supports
#         node sharing instead of full tailnet membership.
#      b. Write an ACL policy (Access Controls) that restricts artist
#         accounts/devices to reaching mercury on tcp:445 only - they
#         should not be able to reach uranus, your LAN, or each other.
#         This is the actual security boundary for external artists;
#         the Samba "valid users"/"hosts allow" rules in
#         samba-shares.nix are defense in depth on top of it, not a
#         substitute for it.
#
# 3. Create the matching Samba-only login (see configuration.nix for the
#    artists group/account pattern), then set its Samba password on
#    mercury:
#        sudo smbpasswd -a <artist-username>
#
# 4. Have the artist connect to \\<mercury-tailscale-name>\Shop-Inbox
#    (Tailscale assigns a MagicDNS name - check with `tailscale status`)
#    using that username/password.
{pkgs, ...}: {
  services.tailscale.enable = true;

  environment.systemPackages = [pkgs.tailscale];
}
