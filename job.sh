#!/bin/bash

# Keep workload files on the persistent home volume.
mkdir -p "$HOME/$WORKDIR" || exit 1
cd "$HOME/$WORKDIR" || exit 1

# Add workload dependencies here.
sudo apt-get update || exit 1
sudo apt-get install -y --no-install-recommends curl git python3 || exit 1

# Replace this sample result and archive with workload outputs.
echo 'Provisioning complete. Replace job.sh with your workload.' > result.txt || exit 1
tar -czf "$ARTIFACT_NAME" result.txt
