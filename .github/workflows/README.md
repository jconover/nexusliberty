# CI/CD Workflows

NexusLiberty uses GitHub Actions for pre-merge quality gates and Tekton/ArgoCD for on-cluster deployment.

## Workflows

### liberty-build.yml

Triggers on push to `main` when `docker/liberty-app/**` or `app/**` change.

1. Builds the Liberty Docker image (multi-stage Maven + Open Liberty)
2. Runs Trivy vulnerability scan
3. Pushes to GHCR with SHA-based tag
4. Triggers the Tekton pipeline on-cluster (via self-hosted runner) which updates the image tag in `WebSphereLibertyApplication.yaml` and commits to `main`
5. ArgoCD detects the manifest change and syncs the new deployment to OKD

### ihs-build.yml

Triggers on push to `main` and on pull requests when `docker/ihs/**` changes.

1. Builds the IHS (Apache HTTPD) image
2. Pushes to GHCR (push to main only)

PR triggers allow previewing IHS config changes before merging.

### ansible-lint.yml

Triggers on push to `main`, pull requests, and manual dispatch (`workflow_dispatch`).

1. Installs ansible-lint from pinned version in `ansible/requirements-lint.txt`
2. Lints all playbooks and roles under `ansible/`

## Deployment Flow

```
Code push → GitHub Actions (build + scan + push) → Tekton (manifest update)
  → Git commit → ArgoCD (detect + sync) → OKD (rolling deployment)
```

## Security

- All actions are pinned to commit SHAs (not `@latest` or `@v*`)
- Minimal `permissions:` declared per workflow
- Path filters prevent unnecessary builds
- GHCR credentials use `GITHUB_TOKEN` (no PATs in workflows)
