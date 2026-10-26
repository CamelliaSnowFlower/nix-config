# Prompt 6 — Consolidate and Harden Container Services

Review the Odysseus module, Ollama, sticker n8n/Podman configuration, Tailscale exposure, systemd dependencies, secret files, and firewall rules. Extract only genuinely shared policies—image pinning, port binding, environment-file handling, persistence/ownership, health checks, hardening—while keeping service networks, secrets, data, and restart behavior isolated.

Verify current documentation for the locked versions. Review `N8N_WEBHOOK_URL`, `N8N_EDITOR_BASE_URL`, `N8N_PROXY_HOPS`, `NODES_EXCLUDE`, `N8N_RESTRICT_FILE_ACCESS_TO`, and the fact that Execute Command is not sandboxed by the file-node path restriction. Keep n8n loopback-bound behind Tailscale; do not add Funnel or public port forwarding. Never expose Shop-Accounting to the sticker container or put secrets in the Nix store. Pin mutable `latest` tags after deciding and testing target releases.

Assess the stale Uranus TCP 7125 exception against Odysseus' default loopback port 7000, and the `nofail` Ollama model bind mount. Produce a risk matrix first; implement in bounded changes with per-host evaluation. Do not deploy or restart production services.
