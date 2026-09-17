#!/usr/bin/env bash

# Load required docker images onto image registry
# Usage: ./load-images.sh [REGISTRY_NAME]

if [ "$1" ]; then
  MW_REGISTRY="mw-docker.repositories.mathworks.com"
  CS="com.mathworks.cloudservices"
  PS="com.mathworks.polyspace.center"
  REPO_CS="${MW_REGISTRY}/${CS}"
  REPO_PS="${MW_REGISTRY}/${PS}"
  REPO_CS_EX="${1}/${CS}"
  REPO_PS_EX="${1}/${PS}"

  USERMANAGER_VERSION="2.45.0"
  ISSUETRACKER_VERSION="3.10.0"
  POLYSPACE_VERSION="26.1.0"

  echo "** Download images from distribution"
  for i in *.tar; do
    cat $i | docker load
  done
  echo "** Images downloaded"

  echo "** Re-tag image registry from ${MW_REGISTRY} to ${1}"
  echo "** Select only required images"

  docker tag "${REPO_CS}.usermanager.usermanager-webui:${USERMANAGER_VERSION}" "${REPO_CS_EX}.usermanager.usermanager-webui:${USERMANAGER_VERSION}"
  docker tag "${REPO_CS}.usermanager.usermanager-image:${USERMANAGER_VERSION}" "${REPO_CS_EX}.usermanager.usermanager-image:${USERMANAGER_VERSION}"
  docker tag "${REPO_CS}.usermanager.usermanager-db:${USERMANAGER_VERSION}" "${REPO_CS_EX}.usermanager.usermanager-db:${USERMANAGER_VERSION}"

  docker tag "${REPO_CS}.issuetracker.issuetracker-web-image:${ISSUETRACKER_VERSION}" "${REPO_CS_EX}.issuetracker.issuetracker-web-image:${ISSUETRACKER_VERSION}"
  docker tag "${REPO_CS}.issuetracker.issuetracker-image:${ISSUETRACKER_VERSION}" "${REPO_CS_EX}.issuetracker.issuetracker-image:${ISSUETRACKER_VERSION}"

  docker tag "${REPO_PS}.web-server:${POLYSPACE_VERSION}" "${REPO_PS_EX}.web-server:${POLYSPACE_VERSION}"
  docker tag "${REPO_PS}.etl:${POLYSPACE_VERSION}" "${REPO_PS_EX}.etl:${POLYSPACE_VERSION}"
  docker tag "${REPO_PS}.db:${POLYSPACE_VERSION}" "${REPO_PS_EX}.db:${POLYSPACE_VERSION}"

  echo "** Images re-tagged"
  echo "** Push images to ${1}"

  docker push "${REPO_CS_EX}.usermanager.usermanager-webui:${USERMANAGER_VERSION}"
  docker push "${REPO_CS_EX}.usermanager.usermanager-image:${USERMANAGER_VERSION}"
  docker push "${REPO_CS_EX}.usermanager.usermanager-db:${USERMANAGER_VERSION}"

  docker push "${REPO_CS_EX}.issuetracker.issuetracker-web-image:${ISSUETRACKER_VERSION}"
  docker push "${REPO_CS_EX}.issuetracker.issuetracker-image:${ISSUETRACKER_VERSION}"

  docker push "${REPO_PS_EX}.web-server:${POLYSPACE_VERSION}"
  docker push "${REPO_PS_EX}.etl:${POLYSPACE_VERSION}"
  docker push "${REPO_PS_EX}.db:${POLYSPACE_VERSION}"

else
  echo "Error: Image registry name not provided"
  echo "Usage load-images.sh [REGISTRY_NAME]"
  exit 1
fi

exit
