#!/usr/bin/env bash

set -euo pipefail

# This program will read a list of Scala and SBT versions from build config
# files. For each pair of versions, it will determine if a version already exists
# on docker hub for that version. If it does it skips that version.

# A FORCE env var can be set to 1 (one) in order to force the building of all version
# pairs of Scala and SBT regardless of whether or not they already exist on dockerhub.
# This is useful to ensure the docker image has the newest JDK version since currently
# only the major version (8) is specified for JDK and the script will get whatever the
# latest version 8 of JDK exists at the time of build.

declare -r FORCE=${FORCE:-0}
declare -r REPO="broadinstitute/scala"
declare -r JDK_VERSION=8

declare -r SCRIPT_DIR=$(cd $(dirname $0) && pwd)
declare -r SCALA_CONFIG=${SCRIPT_DIR}/scala-list.cfg
declare -r SBT_CONFIG=${SCRIPT_DIR}/sbt-list.cfg
declare -r DOCKERFILE_TEMPLATE=${SCRIPT_DIR}/Dockerfile.tmpl
declare -r DOCKERFILE=${SCRIPT_DIR}/Dockerfile

declare -r VALID_VERSION_PATTERN='^[a-zA-Z0-9]+'

function check_config () {
  local -r config=$1

  if [ -f "$config" ]; then
    if ! grep -Eq ${VALID_VERSION_PATTERN} ${config}; then
      2>&1 echo No valid entries in config file: ${config}
      exit 1
    fi
  else
    2>&1 echo Missing version list: ${config}
    exit 1
  fi
}

function check_should_build () {
  local -r docker_tag=$1

  2>&1 echo Checking if image ${docker_tag} needs to be built...

  if ! docker pull ${REPO}:${docker_tag}; then
    return 0
  else
    2>&1 echo Image already built, skipping
    return 1
  fi
}

function build_docker () {
  local -r scala_version=$1 sbt_version=$2
  local -r docker_tag=scala-${scala_version}-sbt-${sbt_version}

  if [ ${FORCE} -eq 1 ] || check_should_build ${docker_tag}; then
    2>&1 echo Building docker ${REPO}:${docker_tag}

    # Build Dockerfile from template
    sed -e "s;SCALA_VERSION_TAG;${scala_version};" \
        -e "s;SBT_VERSION_TAG;${sbt_version};" \
        -e "s;JDK_VERSION_TAG;${JDK_VERSION};" \
        < ${DOCKERFILE_TEMPLATE} > ${DOCKERFILE}

    # Add some Jenkins labels to designate this build
    echo LABEL GIT_BRANCH=${GIT_BRANCH} >> ${DOCKERFILE}
    echo LABEL GIT_COMMIT=${GIT_COMMIT} >> ${DOCKERFILE}
    echo LABEL BUILD_URL=${BUILD_URL} >> ${DOCKERFILE}

    docker build --pull -t ${REPO}:${docker_tag} .

    2>&1 echo Tagging docker ${REPO}:${docker_tag}_${BUILD_NUMBER}
    docker tag ${REPO}:${docker_tag} ${REPO}:${docker_tag}_${BUILD_NUMBER}

    2>&1 echo Pushing docker ${REPO}:${docker_tag}
    docker push ${REPO}:${docker_tag}

    2>&1 echo Pushing docker ${REPO}:${docker_tag}_${BUILD_NUMBER}
    docker push ${REPO}:${docker_tag}_${BUILD_NUMBER}

    2>&1 echo Cleaning up pulled and built images
    docker rmi ${REPO}:${docker_tag} ${REPO}:${docker_tag}_${BUILD_NUMBER}
  fi
}

function main () {
  for config in ${SCALA_CONFIG} ${SBT_CONFIG}; do
    check_config ${config}
  done

  trap "rm -f ${DOCKERFILE}" EXIT

  grep -E ${VALID_VERSION_PATTERN} ${SCALA_CONFIG} | while read scala_version; do
    grep -E ${VALID_VERSION_PATTERN} ${SBT_CONFIG} | while read sbt_version; do
      build_docker ${scala_version} ${sbt_version}
    done
  done
}

main
