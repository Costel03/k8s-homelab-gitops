#!/bin/bash
#
# build-base-box.sh — Run from WSL. Build the local k8s-base Vagrant box.
#
# Run ONCE (or when you want fresh packages in the base image).
# The box survives 'vagrant.exe destroy' on the main cluster.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building base box from base-box/Vagrantfile..."
cd "$SCRIPT_DIR/base-box"

# Remove any stale base template VM
vagrant.exe destroy -f 2>/dev/null || true

# Boot and provision
vagrant.exe up

# Package into a .box file
vagrant.exe package --output "$SCRIPT_DIR/k8s-base.box"

# Tear down the temp VM
vagrant.exe destroy -f

cd "$SCRIPT_DIR"

# Register locally (--force replaces any existing version)
vagrant.exe box add k8s-base ./k8s-base.box --force

rm -f ./k8s-base.box

echo ""
echo "==> Done! Base box 'k8s-base' is registered."
echo "    Run './up.sh' to start the cluster."
