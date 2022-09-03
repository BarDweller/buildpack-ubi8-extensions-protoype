#!/bin/bash

OUTPUT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/build-artifacts
mkdir -p ${OUTPUT_DIR}

IMG_TAG=$1
REGISTRY_HOST=$2
LIFECYCLE_IMG=$3

cat << EOF > ${OUTPUT_DIR}/builder.toml
description = "ubi8 builder image"
[lifecycle]
  version = "0.13.3"
[stack]
  id = "${IMG_TAG}"
  build-image = "${REGISTRY_HOST}/builder-base:${IMG_TAG}"
  run-image = "${REGISTRY_HOST}/run:${IMG_TAG}"
EOF

cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-image
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

echo -n ">>>>>>>>>> Removing old build/run image..."
docker image rm $REGISTRY_HOST/builder-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/builder:${IMG_TAG} --force

echo ">>>>>>>>>> Building build base image..."
docker build . -t $REGISTRY_HOST/builder-base:${IMG_TAG} --target base -f ${OUTPUT_DIR}/Dockerfile.build-image 
echo ">>>>>>>>>> Building run base image..."
docker build . -t $REGISTRY_HOST/run:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-image

echo ">>>>>>>>>> Pack creating builder image..."
pack builder create $REGISTRY_HOST/builder-pack:${IMG_TAG} --config ${OUTPUT_DIR}/builder.toml

docker push $REGISTRY_HOST/builder-base:${IMG_TAG}
docker push $REGISTRY_HOST/run:${IMG_TAG}
docker push $REGISTRY_HOST/builder-pack:${IMG_TAG}

#Update the newly created builder with buildpacks from paketo and lifecycle from the lifecycle image.
cat <<EOF >${OUTPUT_DIR}/Dockerfile.withlifecycle
FROM $LIFECYCLE_IMG as lifecycle
FROM $REGISTRY_HOST/builder-pack:${IMG_TAG}
COPY ./paketo-java /cnb/buildpacks
COPY ./extensions /cnb/extensions
COPY ./order.toml /cnb/order.toml
COPY --from=lifecycle /lifecycle /cnb/lifecycle
EOF
docker build . -t $REGISTRY_HOST/builder:${IMG_TAG} -f ${OUTPUT_DIR}/Dockerfile.withlifecycle
docker push $REGISTRY_HOST/builder:${IMG_TAG}

