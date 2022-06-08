#!/bin/env bash

# Build the Docker container
# Args
#  tag: the tag to use for the container (default: latest)

tag_base="timimages/dumbo"
tag=${1:-latest}
current_commit=$(git rev-parse HEAD)
current_commit_date=$(git show -s --format=%cd --date=short)

docker build -t "$tag_base:$tag" -t "$tag_base:$current_commit" .