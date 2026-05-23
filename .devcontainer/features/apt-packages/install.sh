#!/bin/sh
set -e

PACKAGES="${PACKAGES:-}"

if [ -z "$PACKAGES" ]; then
  echo "No packages specified, skipping."
  exit 0
fi

apt-get update
apt-get install -y --no-install-recommends $PACKAGES
rm -rf /var/lib/apt/lists/*
