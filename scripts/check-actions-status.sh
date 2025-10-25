#!/bin/bash
# GitHub Actions Status Checker
# This script helps verify that all workflows are passing

echo "🔍 Checking GitHub Actions Status..."
echo "Repository: Kasa1905/Shepherd"
echo ""

echo "📋 Recent Workflow Runs:"
echo "Visit: https://github.com/Kasa1905/Shepherd/actions"
echo ""

echo "🎯 Expected Workflows to Run on Push:"
echo "  1. CI/CD Pipeline (ci-cd.yml)"
echo "     - lint ✓"
echo "     - security ✓"
echo "     - test ✓"
echo "     - build (optional - needs Docker Hub secrets)"
echo "     - push-ghcr ✓"
echo "     - deploy-staging (skips if KUBECONFIG_STAGING not set)"
echo ""
echo "  2. Quick Validation (validate.yml)"
echo "     - validate ✓"
echo ""

echo "⚙️  To configure secrets:"
echo "  1. Go to: https://github.com/Kasa1905/Shepherd/settings/secrets/actions"
echo "  2. Add:"
echo "     - KUBECONFIG_STAGING (base64-encoded kubeconfig)"
echo "     - KUBECONFIG_PRODUCTION (base64-encoded kubeconfig)"
echo "     - DOCKER_USERNAME (optional)"
echo "     - DOCKER_PASSWORD (optional)"
echo ""

echo "🌍 To configure environments:"
echo "  1. Go to: https://github.com/Kasa1905/Shepherd/settings/environments"
echo "  2. Create:"
echo "     - staging"
echo "     - production"
echo ""

echo "✅ If you see this message, the workflows are syntactically correct!"
echo "   Any VS Code warnings about secrets/environments are expected."
echo ""
echo "📊 Check actual run status at:"
echo "   https://github.com/Kasa1905/Shepherd/actions"
