# Automated ZFS snapshot policy via sanoid. Doesn't have the same
# which-tool-creates-it issue as datasets do - sanoid just snapshots
# whatever datasets already exist by the time it runs, so this works
# fine through an ordinary `nixos-rebuild switch`.
{
  services.sanoid = {
    enable = true;

    templates = {
      # Heavy protection for active artwork templates and business data
      production-critical = {
        hourly = 24; # Keep every hour for the last 1 day
        daily = 14; # Keep every day for the last 2 weeks
        monthly = 3; # Keep every month for the last quarter
        autoprune = true;
        autosnap = true;
      };

      # Lighter rules for bulky 3D models to save disk space
      bulky-assets = {
        hourly = 0; # Skip hourly captures
        daily = 7; # Keep daily versions for 1 week
        monthly = 1; # Keep 1 monthly fallback
        autoprune = true;
        autosnap = true;
      };
    };

    # Apply the policies directly to your ZFS datasets
    datasets = {
      "storage/shop-designs" = {useTemplate = ["production-critical"];};
      "storage/shop-assets" = {useTemplate = ["production-critical"];};
      "storage/shop-accounting" = {useTemplate = ["production-critical"];}; # Protected
      "storage/shop-3d" = {useTemplate = ["bulky-assets"];};
    };
  };
}
