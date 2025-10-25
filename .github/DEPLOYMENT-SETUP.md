# GitHub Actions Deployment Setup

This document explains how to configure automatic deployments to Kubernetes clusters (staging and production) in the CI/CD pipeline.

## Overview

The CI/CD pipeline (`ci-cd.yml`) includes optional deployment jobs that are **disabled by default**. This allows the pipeline to run successfully even if you haven't set up Kubernetes clusters yet.

## Current Pipeline Status

✅ **Always Runs:**
- Code quality & linting
- Security scanning (bandit, safety, gitleaks)
- Unit tests (pytest)
- Docker image build
- Push to GitHub Container Registry (GHCR)

⚠️ **Disabled by Default:**
- Deploy to Staging
- Deploy to Production

## Enabling Deployments

To enable automatic deployments, you need to configure repository variables and secrets.

### 1. Enable Staging Deployments

**Step 1: Create Repository Variable**
1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click on the **Variables** tab
4. Click **New repository variable**
5. Create variable:
   - **Name:** `STAGING_ENABLED`
   - **Value:** `true`

**Step 2: Add Kubernetes Config Secret**
1. In the same **Secrets and variables** → **Actions** page
2. Click on the **Secrets** tab
3. Click **New repository secret**
4. Create secret:
   - **Name:** `KUBECONFIG_STAGING`
   - **Value:** Base64-encoded kubeconfig file
   
   To encode your kubeconfig:
   ```bash
   cat ~/.kube/config | base64 | tr -d '\n'
   ```

**Step 3: Create Staging Environment**
1. Go to **Settings** → **Environments**
2. Click **New environment**
3. Name it: `staging`
4. Configure protection rules if desired (e.g., required reviewers)

### 2. Enable Production Deployments

**Step 1: Create Repository Variable**
1. Create variable:
   - **Name:** `PRODUCTION_ENABLED`
   - **Value:** `true`

**Step 2: Add Kubernetes Config Secret**
1. Create secret:
   - **Name:** `KUBECONFIG_PRODUCTION`
   - **Value:** Base64-encoded kubeconfig for production cluster

**Step 3: Create Production Environment**
1. Create environment: `production`
2. **Recommended:** Enable required reviewers for production deployments
3. **Recommended:** Enable deployment branches rule (only `main`)

### 3. Prepare Helm Values Files

Ensure your Helm values files exist and are properly configured:
- `helm/shepherd/values-staging.yaml` - Staging configuration
- `helm/shepherd/values-prod.yaml` - Production configuration

## Deployment Workflow

### Staging Deployment
- **Trigger:** Automatic on every push to `main` branch (if `STAGING_ENABLED=true`)
- **Requires:** 
  - `KUBECONFIG_STAGING` secret
  - `staging` environment configured
- **Process:**
  1. Installs kubectl and Helm
  2. Configures kubeconfig from secret
  3. Runs `./scripts/deploy.sh` with staging values
  4. Runs smoke tests (waits for pods to be ready)
  5. Posts deployment status

### Production Deployment
- **Trigger:** Manual workflow dispatch (if `PRODUCTION_ENABLED=true`)
- **Requires:**
  - `KUBECONFIG_PRODUCTION` secret
  - `production` environment configured
  - Manual approval (if configured in environment protection rules)
- **Process:**
  1. Same as staging but uses production values
  2. Includes additional validation steps
  3. Posts deployment status

## Manual Deployment Trigger

To manually trigger a production deployment:
1. Go to **Actions** tab in your repository
2. Select **CI/CD Pipeline** workflow
3. Click **Run workflow**
4. Select branch (usually `main`)
5. Click **Run workflow** button

## Testing Without Kubernetes

If you don't have Kubernetes clusters yet, the pipeline will still work perfectly:
- All build, test, and security jobs will run
- Docker images will be pushed to GHCR
- Deployment jobs will be skipped (no errors)

You can test locally using:
```bash
# Local development
./setup-local.sh

# Local Docker Compose
docker-compose -f docker-compose.local.yml up
```

## Troubleshooting

### Deployment job not running
- Check if `STAGING_ENABLED` or `PRODUCTION_ENABLED` variable is set to `true`
- Verify the variable is created in repository settings (not environment settings)

### Kubeconfig errors
- Ensure the secret is base64-encoded correctly
- Verify the kubeconfig has correct cluster and credentials
- Test kubeconfig locally: `kubectl --kubeconfig=/path/to/config get nodes`

### Helm deployment fails
- Check that Helm chart is valid: `helm lint helm/shepherd`
- Verify values files exist and are valid YAML
- Check namespace exists in cluster: `kubectl get namespace staging`

### Permission issues in deployment script
- The script now uses workspace-relative log files
- No sudo permissions needed
- Logs will be in: `shepherd-deploy.log`, `shepherd-canary.log`, etc.

## Security Best Practices

1. **Never commit kubeconfig files** - Always use secrets
2. **Use separate clusters** for staging and production
3. **Enable environment protection rules** for production
4. **Rotate kubeconfig credentials** regularly
5. **Use service accounts** with minimal required permissions
6. **Enable deployment approval** for production environment

## Next Steps

1. Set up Kubernetes clusters (staging and production)
2. Create repository variables to enable deployments
3. Add kubeconfig secrets
4. Configure environment protection rules
5. Test staging deployment on next push to main
6. Manually test production deployment

## References

- [GitHub Actions Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Helm Documentation](https://helm.sh/docs/)
- [kubectl Documentation](https://kubernetes.io/docs/reference/kubectl/)
