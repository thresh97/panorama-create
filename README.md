# panorama-create

> **FOR LAB AND DEMONSTRATION USE ONLY.**
> This code is provided without warranty of any kind, express or implied. It is not validated for production use. No support is provided. Use at your own risk.

Terraform deployments for a Palo Alto Networks Panorama management VM across cloud providers.

This is **Phase 1** of a two-phase deployment workflow. After deploying Panorama here, bootstrap and configure it, then use the network ID output in the [vmseries-architectures](https://github.com/thresh97/vmseries-architectures) deployment to peer firewalls to Panorama.

## Cloud Providers

| Provider | Directory | Status |
|----------|-----------|--------|
| Azure | [`azure/`](azure/) | Available |
| AWS | [`aws/`](aws/) | Available |
| GCP | `gcp/` | Coming soon |

## Two-Phase Deployment Workflow

```
Phase 1 (this repo)           Phase 2
panorama-create/              vmseries-architectures/
  azure/  ──────────────────▶  azure/
  aws/    ──────────────────▶  aws/
  gcp/    ──────────────────▶  gcp/
```

Each cloud provider deployment outputs a network ID that you pass into the corresponding `vmseries-architectures` deployment to peer the firewall VNETs to Panorama.

## Usage

See the README in the relevant cloud provider subdirectory.
