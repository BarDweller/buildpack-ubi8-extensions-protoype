#!/bin/bash

# Check the prototype-pack has been built.
if [[ ! -f ../prototype-pack/pack/out/pack ]]; then
  echo "You need to build the prototype-pack directory first, to create the pack binary"
  exit 1
fi

CURRENTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PACK=$CURRENTDIR/../prototype-pack/pack/out/pack

# Create git ignored dir to store the dockerfiles etc we're about to create & use
OUTPUT_DIR=$CURRENTDIR/build-artifacts
mkdir -p ${OUTPUT_DIR}

# Args 
IMG_TAG=$1
REGISTRY_HOST=$2

CNB_USER_ID=1000
CNB_GROUP_ID=1000

# Create builder.toml this MUST correctly reference the builder base image, and run image
# The stack id MUST match the ones in the CNB_STACK_ID env vars in builder base & run images.
# We'll create the builder & run images to match this in a mo.
#
# Note that the stack defined here has a run image of ubi minimal, _without_ java.
cat << EOF > ${OUTPUT_DIR}/builder.toml
# Buildpacks to include in the builder... 
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_nodejs/0.27.0"
  version = "0.27.0"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_node-start/0.8.6"
  version = "0.8.6"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_node-engine/0.19.0"
  version = "0.19.0"  
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_node-run-script/0.5.1"
  version = "0.5.1"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_node-module-bom/0.4.3"
  version = "0.4.3"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_npm-start/0.10.3"
  version = "0.10.3"  
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_yarn/0.8.5"
  version = "0.8.5"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_yarn-start/0.8.6"
  version = "0.8.6"  
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_ca-certificates/3.4.0"
  version = "3.4.0"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_watchexec/2.7.0"
  version = "2.7.0"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_datadog/2.5.0"
  version = "2.5.0"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_image-labels/4.3.0"
  version = "4.3.0"  
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_procfile/5.4.0"
  version = "5.4.0"
[[buildpacks]]
  uri = "file://./nodejs/paketo-buildpacks_environment-variables/4.3.0"
  version = "4.3.0"

# Extensions to include in the builder.. 
[[extensions]]
    id = "redhat-runtimes/nodejs"
    version = "0.0.1"
    uri = "file://./extensions/redhat-runtimes_nodejs/0.0.1"

# Order for extension detection.
[[order-extensions]]
  [[order-extensions.group]]
    id = "redhat-runtimes/nodejs"
    version = "0.0.1"

# Order for buildpack detection.    
[[order]]
  [[order.group]]
    id = "paketo-buildpacks/nodejs"
    version = "0.27.0"

# Override lifecycle version to release candidate with extension support
[lifecycle]
  uri = "https://github.com/buildpacks/lifecycle/releases/download/v0.15.0-rc.1/lifecycle-v0.15.0-rc.1+linux.x86-64.tgz"

# Define the stack
[stack]
  id = "${IMG_TAG}"
  build-image = "${REGISTRY_HOST}/builder-base:${IMG_TAG}"
  run-image = "${REGISTRY_HOST}/run-base:${IMG_TAG}"
EOF

# Create the dockerfile for the java run image, in this case just ubi java, with env vars 
# and uid/gid set for use as a CNB run image.
# This is the image that will be used 
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-java-image
FROM registry.access.redhat.com/ubi8/openjdk-11-runtime:latest as base
ENV CNB_USER_ID=${CNB_USER_ID}
ENV CNB_GROUP_ID=${CNB_GROUP_ID}
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

# Create the dockerfile for the nodejs run image, in this case just
# ubi8/nodejs-16-minimal with env vars and uid/gid set for use as a CNB run image.
# This is the image that will be used
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-nodejs-image
FROM registry.access.redhat.com/ubi8/nodejs-16-minimal as base
ENV CNB_USER_ID=${CNB_USER_ID}
ENV CNB_GROUP_ID=${CNB_GROUP_ID}
ENV CNB_STACK_ID="${IMG_TAG}"
ENV CNB_STACK_DESC="ubi nodejs run image base"
LABEL io.buildpacks.stack.id="${IMG_TAG}"
FROM base as run
USER \${CNB_USER_ID}:\${CNB_GROUP_ID}
EOF

# Create the dockerfile for the base run image, in this case just ubi minimal, with env vars 
# and uid/gid set for use as a CNB run image.
cat <<EOF > ${OUTPUT_DIR}/Dockerfile.run-base-image
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as base
ENV CNB_USER_ID=${CNB_USER_ID}
ENV CNB_GROUP_ID=${CNB_GROUP_ID}
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
ENV CNB_USER_ID=${CNB_USER_ID}
ENV CNB_GROUP_ID=${CNB_GROUP_ID}
ENV CNB_STACK_ID="${IMG_TAG}"
ENV CNB_STACK_DESC="ubi common builder base"
LABEL io.buildpacks.stack.id="${IMG_TAG}"
USER 0
RUN microdnf install --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
  shadow-utils && microdnf clean all && groupadd cnb --gid \${CNB_GROUP_ID} && \
  useradd --uid \${CNB_USER_ID} --gid \${CNB_GROUP_ID} -m -s /bin/bash cnb
RUN mkdir /cnb && mkdir /cnb/extensions && chmod -R 755 /cnb
USER \${CNB_USER_ID}:\${CNB_GROUP_ID}
EOF

# Clean up if we've built these before.
echo -n ">>>>>>>>>> Removing old build/run image..."
docker image rm $REGISTRY_HOST/builder-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-java:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-nodejs:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/builder:${IMG_TAG} --force

# Patch the java run img tag into the generate script, so the run.Dockerfile
# can be generated with the name of the run image we're defining in this script.
echo -n ">>>>>>>>>> Patching generate script with image tag..."
sed -i "s#^FROM localhost:5000/run-java:.*#FROM localhost:5000/run-java:${IMG_TAG}#" extensions/redhat-runtimes_java/0.0.1/bin/generate
sed -i "s#^FROM localhost:5000/run-nodejs:.*#FROM localhost:5000/run-nodejs:${IMG_TAG}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed -i "s#^CNB_USER_ID=.*#CNB_USER_ID=${CNB_USER_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed -i "s#^CNB_GROUP_ID=.*#CNB_GROUP_ID=${CNB_GROUP_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate

# Use docker to create the images for builder-base & run. 
echo ">>>>>>>>>> Building build base image..."
docker build . -t $REGISTRY_HOST/builder-base:${IMG_TAG} --target base -f ${OUTPUT_DIR}/Dockerfile.build-image 
echo ">>>>>>>>>> Building run base image..."
docker build . -t $REGISTRY_HOST/run-base:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-base-image
echo ">>>>>>>>>> Building run java image..."
docker build . -t $REGISTRY_HOST/run-java:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-java-image
echo ">>>>>>>>>> Building run nodejs image..."
docker build . -t $REGISTRY_HOST/run-nodejs:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-nodejs-image

# Use pack to consume the buider-base and output a viable builder image.
echo ">>>>>>>>>> Pack creating builder image..."
$PACK config experimental true
$PACK builder create $REGISTRY_HOST/builder:${IMG_TAG} --config ${OUTPUT_DIR}/builder.toml

RC=$?
echo "builder rc : $RC"

# Send all the currently built stuff off to the registry.
docker push $REGISTRY_HOST/builder-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-java:${IMG_TAG}
docker push $REGISTRY_HOST/run-nodejs:${IMG_TAG}
docker push $REGISTRY_HOST/builder:${IMG_TAG}


