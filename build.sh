#!/bin/env bash

# Build the Docker container
# Args
#  --tag: the tag to use for the container (default: latest)
#  --push: if specified, push the container to Docker Hub

# parse args
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        --tag)
            tag="$2"
            shift
            ;;
        --push)
            push=1
            ;;
        *)
            echo "Unknown argument: $key"
            exit 1
            ;;
    esac
    shift
done

tag_base="timimages/dumbo"
tag=${1:-latest}
current_commit=$(git rev-parse HEAD)
current_commit_date=$(git show -s --format=%cd --date=format:%Y-%m-%d HEAD)

docker build -t "$tag_base:$tag" -t "$tag_base:$current_commit_date-$current_commit" .

if [ -n "$push" ]; then
    docker push "$tag_base:$tag"
    docker push "$tag_base:$current_commit_date-$current_commit"
fi