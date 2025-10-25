# GitHub Actions Workflows

This directory contains CI/CD workflows for the Shepherd Configuration Management System.

## Workflows

### 1. CI/CD Pipeline (`ci-cd.yml`)
Main pipeline for continuous integration and deployment.

**Triggers:**
- Push to `main` branch
- Pull requests to `main`
- Manual workflow dispatch (for production deployments)

**Jobs:**
- **lint**: Code quality checks (flake8, black)
- **security**: Security scanning (bandit, safety)
- **test**: Unit tests with coverage (pytest)
- **build**: Build Docker image and push to Docker Hub (optional)
- **push-ghcr**: Build and push to GitHub Container Registry
- **deploy-staging**: Auto-deploy to staging environment
- **deploy-production**: Manual deployment to production (workflow_dispatch only)

**Required Secrets:**
- `KUBECONFIG_STAGING` - Base64-encoded kubeconfig for staging cluster
- `KUBECONFIG_PRODUCTION` - Base64-encoded kubeconfig for production cluster

**Optional Secrets:**
- `DOCKER_USERNAME` - Docker Hub username (if using Docker Hub)
- `DOCKER_PASSWORD` - Docker Hub password/token (if using Docker Hub)

**Required Environments:**
Create these in GitHub Settings → Environments:
- `staging`
- `production`

### 2. Rollback Workflow (`rollback.yml`)
Manual rollback for staging or production deployments.

**Triggers:**
- Manual workflow dispatch only

**Inputs:**
- `environment`: Choose staging or production
- `revision`: Target revision number (optional, defaults to previous)
- `reason`: Reason for rollback (required)

**Required Secrets:**
- `KUBECONFIG_STAGING` or `KUBECONFIG_PRODUCTION` (depending on environment)

### 3. Quick Validation (`validate.yml`)
Fast syntax and dependency validation.

**Triggers:**
- Push to `main` branch
- Pull requests to `main`

**Jobs:**
- Python syntax validation
- Dependency installation check
- Helm chart linting

## Setup Instructions

### 1. Configure Secrets

Navigate to: **Settings → Secrets and variables → Actions → New repository secret**

Create the following secrets:

```bash
# Generate base64-encoded kubeconfig
cat ~/.kube/config | base64 | pbcopy  # macOS
cat ~/.kube/config | base64 -w 0      # Linux

# Add as KUBECONFIG_STAGING or KUBECONFIG_PRODUCTION
```

### 2. Create Environments

Navigate to: **Settings → Environments → New environment**

Create:
- **staging** - No protection rules needed for auto-deploy
- **production** - Recommended: Add required reviewers for manual approval

### 3. Test the Pipeline

**Automatic (on push to main):**
```bash
git push origin main
# Triggers: lint → security → test → build → push-ghcr → deploy-staging
```

**Manual production deployment:**
1. Go to: **Actions → CI/CD Pipeline → Run workflow**
2. Select deployment strategy: rolling, blue-green, or canary
3. Optional: Specify image tag (defaults to `latest`)
4. For canary: Enable auto-promote if desired

**Manual rollback:**
1. Go to: **Actions → Rollback Deployment → Run workflow**
2. Select environment (staging or production)
3. Optional: Specify revision number
4. Enter rollback reason

## Deployment Strategies

### Rolling Update (Default)
- Zero-downtime gradual rollout
- Configurable surge and unavailability
- Automatic health checks

### Blue/Green
- Deploy to inactive environment
- Test and verify
- Instant traffic switch
- Quick rollback capability

### Canary
- Gradual traffic shifting (10% → 25% → 50% → 75% → 100%)
- Metrics validation at each stage
- Automatic or manual promotion
- HPA-aware (prevents autoscaling drift)

## Troubleshooting

### Deploy jobs failing with "secret not found"
**Solution:** Configure required secrets in repository settings

### Deploy jobs skipped
**Solution:** Jobs skip gracefully if secrets aren't configured. Add secrets to enable.

### MongoDB connection issues in tests
**Solution:** The test job uses a MongoDB service container. Check service health in logs.

### Docker Hub push failing
**Solution:** Docker Hub push is optional. Pipeline will continue using GHCR. Add DOCKER_USERNAME/DOCKER_PASSWORD to enable.

### Helm deployment errors
**Solution:** Check kubeconfig secrets are properly base64-encoded and have cluster access.

## Status Badges

Add these to your README.md:

```markdown
![CI/CD Pipeline](https://github.com/Kasa1905/Shepherd/actions/workflows/ci-cd.yml/badge.svg)
![Quick Validation](https://github.com/Kasa1905/Shepherd/actions/workflows/validate.yml/badge.svg)
```

## Notes

- All deploy jobs use `continue-on-error: true` to prevent pipeline failures when secrets aren't configured
- VS Code warnings about missing secrets/environments are expected until configured in GitHub
- The validation workflow provides fast feedback on syntax/dependency issues
- Test coverage reports are uploaded to Codecov (v4)
- Security reports are uploaded as artifacts for review
