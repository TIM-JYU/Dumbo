#!/bin/bash

set -e

cd /e/dumbo

echo "=== Dumbo: build ==="
docker build -t tim-dumbo-test .

if [ $? -ne 0 ]; then
    echo
    echo "BUILD EPÄONNISTUI. Konttia ei muutettu."
    exit 1
fi

echo
echo "=== Build onnistui ==="
echo "Poistetaan vanha testikontti..."

docker rm -f tim-dumbo-test 2>/dev/null || true

echo "=== Käynnistetään uusi Dumbo ==="

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
echo "=== Dumbo käynnistetty ==="
docker ps --filter "name=tim-dumbo-test"

echo
echo "Valmis."