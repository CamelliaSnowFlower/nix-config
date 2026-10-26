# Prompt 3 — Consolidate Home Manager Profiles

Review the Home Manager tree and propose a focused consolidation. Look for duplicated imports of `home-manager/options.nix`, repeated overlays and `allowUnfree`, profile flags, package boundaries for coding/sysadmin/photography/desktop/unstable, and user-specific settings in `aquarius/default.nix` vs `gemini/default.nix`.

Do not flatten the tree into one large module. Keep optional profile modules safe when disabled and user-specific GUI settings out of shared modules. Propose one clear owner for common settings and profile declarations; make a small patch only where it removes real duplication. Preserve each profile's exact package set and which features are enabled for Aquarius and Gemini. Do not change `home.stateVersion`.

Evaluate all three Home Manager outputs and inspect package/derivation changes. Report removals, preserved behavior, architecture assumptions in `mkHome`, and any option that could not be validated.
