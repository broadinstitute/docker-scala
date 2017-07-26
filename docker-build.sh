#!/bin/bash

# This program will read a list of Scala and SBT versions from build config
# files. For each pair of versions, it will determine if a version already exists
# on docker hub for that version. If it does it skips that version.

# A FORCE env var can be set to 1 (one) in order to force the building of all version
# pairs of Scala and SBT regardless of whether or not they already exist on dockerhub.
# This is useful to ensure the docker image has the newest JDK version since currently
# only the major version (8) is specified for JDK and the script will get whatever the
# latest version 8 of JDK exists at the time of build.

FORCE=${FORCE:-0}

# Docker Hub container name
REPO="broadinstitute/scala"

# Hard-code to JDK 8
JDK_VERSION=8

# Files containing version lists
SCALA_CONFIG="scala-list.cfg"
SBT_CONFIG="sbt-list.cfg"

# Generic error outputting function
errorout() {
   if [ $1 -ne 0 ];
        then
        echo "${2}"
        exit $1
    fi
}

for config in "$SCALA_CONFIG" "$SBT_CONFIG"; do
  if [ -f "$config" ]; then
    if [ ! egrep -q "^[a-zA-Z0-9]+" "$config" ]; then
      errorout 1 "No valid entries in config file: ${config}"
    fi
  else
    errorout 1 "Missing version list: ${config}"
  fi
done

egrep "^[a-zA-Z0-9]+" "$SCALA_CONFIG" | while read scala_version rest; do
  egrep "^[a-zA-Z0-9]+" "$SBT_CONFIG" | while read sbt_version rest; do
    docker_version="scala-${scala_version}-sbt-${sbt_version}"
    build_version=1

    # Ensure Dockerfile doesn't exist
    rm -f Dockerfile

    echo "Checking if Scala version (${scala_version}) on SBT version (${sbt_version}) needs to be built..."
    if [ "$FORCE" -ne "1" ]; then
      # See if version exists on docker hub
      docker pull ${REPO}:${docker_version}
      retcode=$?

      if [ "$retcode" -eq "0" ]; then
        echo "Skipping version"
        build_version=0
      fi
    fi

    if [ "$build_version" -eq "1" ]; then
      echo "Building docker (${REPO}:${docker_version})"

      # Build Dockerfile from template
      sed -e "s;SCALA_VERSION_TAG;${scala_version};" -e "s;SBT_VERSION_TAG;${sbt_version};" -e "s;JDK_VERSION_TAG;${JDK_VERSION};" < Dockerfile.tmpl > Dockerfile

      # Add some Jenkins labels to designate this build
      echo "LABEL GIT_BRANCH=${GIT_BRANCH}" >> Dockerfile
      echo "LABEL GIT_COMMIT=${GIT_COMMIT}" >> Dockerfile
      echo "LABEL BUILD_URL=${BUILD_URL}" >> Dockerfile

      docker build --pull -t ${REPO}:${docker_version} .
      retcode=$?
      errorout $retcode "Failed to build docker image"

      echo "Tagging docker (${REPO}:${docker_version}_${BUILD_NUMBER})"
      docker tag ${REPO}:${docker_version} ${REPO}:${docker_version}_${BUILD_NUMBER}
      retcode=$?
      errorout $retcode "Build successful but could not tag to build number"

      echo "Pushing docker (${REPO}:${docker_version})"
      docker push ${REPO}:${docker_version}
      retcode=$?
      errorout $retcode "Failed to push docker image"

      echo "Pushing docker (${REPO}:${docker_version}_${BUILD_NUMBER})"
      docker push ${REPO}:${docker_version}_${BUILD_NUMBER}
      retcode=$?
      errorout $retcode "Failed to push docker tag image"

      # Clean up all pulled built images
      echo "Cleaning up pulled and built images"
      docker rmi ${REPO}:${docker_version}
      retcode=$?
      docker rmi ${REPO}:${docker_version}_${BUILD_NUMBER}
      retcode=$(($retcode + $?))
      errorout $retcode "Some images were not able to be cleaned up"
    fi
  done
done

test -f Dockerfile && rm -f Dockerfile

exit 0
