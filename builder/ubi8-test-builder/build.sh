#!/bin/bash

# Create git ignored dir to store the dockerfiles etc we're about to create & use
OUTPUT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/build-artifacts
mkdir -p ${OUTPUT_DIR}

# Args 
IMG_TAG=$1
REGISTRY_HOST=$2
LIFECYCLE_IMG=$3

# Create builder.toml this MUST correctly reference the builder base image, and run image
# The stack id MUST match the ones in the CNB_STACK_ID env vars in builder base & run images.
cat << EOF > ${OUTPUT_DIR}/builder.toml
description = "ubi8 builder image"
[lifecycle]
  version = "0.13.3"
[stack]
  id = "${IMG_TAG}"
  build-image = "${REGISTRY_HOST}/builder-base:${IMG_TAG}"
  run-image = "${REGISTRY_HOST}/run-base:${IMG_TAG}"
EOF

# Create the dockerfile for the java run image, in this case just ubi java, with env vars 
# and uid/gid set for use as a CNB run image.
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-java-image
FROM registry.access.redhat.com/ubi8/openjdk-11-runtime:latest as base
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID="${IMG_TAG}"
ENV CNB_STACK_DESC="ubi java run image base"
LABEL io.buildpacks.stack.id="${IMG_TAG}"
USER 0
RUN microdnf install --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
  shadow-utils && microdnf clean all && groupadd cnb --gid \${CNB_GROUP_ID} && \
  useradd --uid \${CNB_USER_ID} --gid \${CNB_GROUP_ID} -m -s /bin/bash cnb
USER 1000
FROM base as run
USER \${CNB_USER_ID}:\${CNB_GROUP_ID}
EOF

# Create the dockerfile for the base run image, in this case just ubi java, with env vars 
# and uid/gid set for use as a CNB run image.
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-base-image
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as base
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID="${IMG_TAG}"
ENV CNB_STACK_DESC="ubi minimal run image base"
LABEL io.buildpacks.stack.id="${IMG_TAG}"
USER 0
RUN microdnf install --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
  shadow-utils && microdnf clean all && groupadd cnb --gid \${CNB_GROUP_ID} && \
  useradd --uid \${CNB_USER_ID} --gid \${CNB_GROUP_ID} -m -s /bin/bash cnb
USER 1000
FROM base as run
USER \${CNB_USER_ID}:\${CNB_GROUP_ID}
EOF

# Create the dockerfile for the base build image, this is the image that will be used
# by pack as the base for the builder image. 
# In this case, we're using ubi minimal + env vars & uid/gid customization.
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.build-image
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as base
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID="${IMG_TAG}"
ENV CNB_STACK_DESC="ubi common builder base"
LABEL io.buildpacks.stack.id="${IMG_TAG}"
RUN microdnf install --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
  shadow-utils && microdnf clean all && groupadd cnb --gid \${CNB_GROUP_ID} && \
  useradd --uid \${CNB_USER_ID} --gid \${CNB_GROUP_ID} -m -s /bin/bash cnb
EOF

# Clean up if we've built these before.
echo -n ">>>>>>>>>> Removing old build/run image..."
docker image rm $REGISTRY_HOST/builder-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-java:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/builder:${IMG_TAG} --force

# Patch the current img tag into the generate script =)
echo -n ">>>>>>>>>> Patching generate script with image tag..."
sed -i "s#^FROM localhost:5000/run-java:.*#FROM localhost:5000/run-java:${IMG_TAG}#" extensions/redhat-runtimes_java/0.0.1/bin/generate

# Use docker to create the images for builder-base & run. 
echo ">>>>>>>>>> Building build base image..."
docker build . -t $REGISTRY_HOST/builder-base:${IMG_TAG} --target base -f ${OUTPUT_DIR}/Dockerfile.build-image 
echo ">>>>>>>>>> Building run base image..."
docker build . -t $REGISTRY_HOST/run-base:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-base-image
echo ">>>>>>>>>> Building run java image..."
docker build . -t $REGISTRY_HOST/run-java:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-java-image

# Use pack to consume the buider-base and output a viable builder image.
# Note this isn't the image we actually use, as this builder is basically empty.
echo ">>>>>>>>>> Pack creating builder image..."
pack builder create $REGISTRY_HOST/builder-pack:${IMG_TAG} --config ${OUTPUT_DIR}/builder.toml

# Send all the currently built stuff off to the registry.
docker push $REGISTRY_HOST/builder-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-java:${IMG_TAG}
docker push $REGISTRY_HOST/builder-pack:${IMG_TAG}

# Create a Dockerfile that will customize the pack built builder image
# with buildpacks from paketo and an updated lifecycle from the lifecycle image.
cat <<EOF >${OUTPUT_DIR}/Dockerfile.withlifecycle
FROM $LIFECYCLE_IMG as lifecycle
FROM $REGISTRY_HOST/builder-pack:${IMG_TAG}
COPY ./paketo-java /cnb/buildpacks
COPY ./extensions /cnb/extensions
COPY ./order.toml /cnb/order.toml
COPY --from=lifecycle /lifecycle /cnb/lifecycle
EOF

# Use docker to create an updated builder image with newer lifecycle + test content.
docker build . -t $REGISTRY_HOST/builder:${IMG_TAG} -f ${OUTPUT_DIR}/Dockerfile.withlifecycle
# Send builder to the registry (needed so kaniko can find it there later)
docker push $REGISTRY_HOST/builder:${IMG_TAG}

