#!/bin/bash

# TESTING ONLY — NOT FOR PRODUCTION USE.
#
# This script rebuilds and restarts the Dumbo test container.
#
# IMPORTANT: Stop the production Dumbo container before running this script.
# The test container uses the same Docker network alias, "dumbo", as the
# production service. Running both containers simultaneously may cause
# network alias conflicts or route requests to the wrong container.
#
# The script first builds a new Docker image from the current source code.
# If the build fails, the existing test container is left untouched.
# If the build succeeds, the old test container is removed and a new one
# is started using the newly built image.
#
# The cache and temporary directories are mounted from the host, so their
# contents are preserved when the test container is replaced.

set -e

# Run all commands from the Dumbo source directory.
cd /e/dumbo

echo "=== Dumbo: build ==="

# Build the Docker image from the Dockerfile in the current directory.
docker build -t tim-dumbo-test .

# This check is redundant because 'set -e' already stops the script
# if the build fails. It is retained from the original script.
if [ $? -ne 0 ]; then
    echo
    echo "BUILD FAILED. The existing container has not been changed."
    exit 1
fi

echo
echo "=== Build successful ==="

# Remove the previous test container, if it exists.
# This is done only after the image has been built successfully.
echo "Removing the old test container..."
docker rm -f tim-dumbo-test 2>/dev/null || true

echo "=== Starting the new Dumbo container ==="

# Start a new container using the newly built image.
#
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from rewriting
# Docker's Linux-style paths.
#
# --name: Assign a predictable name to the container.
# --network: Connect to the existing Docker network used by TIM.
# --network-alias: Make Dumbo reachable as 'dumbo' on that network.
# -v: Mount the host cache and temporary directories into the container.
# --read-only: Make the container's root filesystem read-only.
# --restart unless-stopped: Restart automatically unless explicitly stopped.
# --log-driver none: Disable Docker's container log collection.
# -d: Run the container in the background.
MSYS_NO_PATHCONV=1 docker run -d \
  --name tim-dumbo-test \
  --network tim_default \
  --network-alias dumbo \
  -v /e/tim/Dumbo/cache:/dumbo_cache \
  -v /e/tim/Dumbo/tmp:/dumbo_tmp \
  --read-only \
  --restart unless-stopped \
  --log-driver none \
  tim-dumbo-test

echo
echo "=== Dumbo test container started ==="

# Display the status of the new test container.
docker ps --filter "name=tim-dumbo-test"

echo
echo "Done."
