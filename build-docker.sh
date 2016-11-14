#!/bin/bash

# this script will construct the Dockerfile for this build based on 
# the values for these environment vars:
#  - JDK_VERSION
#  - VAULT_VERSION
#  - CONSUL_TEMPLATE_VERSION
#  - SCALA_VERSION
#  - SBT_VERSION

# If any of these environment vars are not set the build will exit with failure

# the Dockerfile template is required to exist in this repo

# Docker Hub container name
REPO="broadinstitute/scala"

# build number hack
BUILD_NUM=${BUILD_NUM:-0}
VERSION_NUM=${VERSION_NUM:-1}
JDK_VERSION=${JDK_VERSION:-8}

# TODO
# check that all vars are set

if [ -z "${JDK_VERSION}" -o -z "${VAULT_VERSION}" -o -z "${CONSUL_TEMPLATE_VERSION}" -o -z "${SCALA_VERSION}" -o -z "${SBT_VERSION} ]
then
    echo "ERROR: Must specify versions that will be part of build"
    exit 1
fi

# build Dockerfile from template

sed -e "s;SCALA_VERSION_TAG;${SCALA_VERSION};" -e "s;SBT_VERSION_TAG;${SBT_VERSION};" -e "s;VAULT_VERSION_TAG;${VAULT_VERSION};" -e "s;CONSUL_TEMPLATE_VERSION_TAG;${CONSUL_TEMPLATE_VERSION};" -e "s;JDK_VERSION_TAG;${JDK_VERSION};" < Dockerfile.tmpl > Dockerfile

# build docker

docker build -t ${REPO}:${VERSION_NUM}.${BUILD_NUM} .
# need to check return status on build

# rm Dockerfile after build
rm -f Dockerfile

docker tag ${REPO}:${VERSION_NUM}.${BUILD_NUM} ${REPO}:scala-${SCALA_VERSION}

