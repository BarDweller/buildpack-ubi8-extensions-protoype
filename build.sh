#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo -e "Usage: build.sh image-tag registry-host\neg. build.sh my-image localhost:5000" >&2
  exit 2
fi

# Args 
IMG_TAG=$1
REGISTRY_HOST=$2

CURRENTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Create git ignored dir to store the dockerfiles etc we're about to create & use
OUTPUT_DIR=${CURRENTDIR}/build-artifacts
mkdir -p ${OUTPUT_DIR}/bin

echo -e "\n>>>>>>>>>> Using : \n  Image Tag: ${IMG_TAG}\n  Registry: ${REGISTRY_HOST}"

# Make sure we use a level of pack that supports image extensions.
PACK=${OUTPUT_DIR}/bin/pack
echo -e "\n>>>>>>>>>> Testing for Pack at : ${PACK}"
if [[ ! -f ${PACK} ]]; then
   echo -e "  - not found, obtaining from github."
   curl -sSL "https://github.com/buildpacks/pack/releases/download/v0.28.0/pack-v0.28.0-linux.tgz" | tar -C ${OUTPUT_DIR}/bin --no-same-owner -xz pack
else
   echo -e "  - found, using pack"
fi

# Create builder.toml this MUST correctly reference the builder base image, and run image
# The stack id MUST match the ones in the CNB_STACK_ID env vars in builder base & run images.
# We'll create the builder & run images to match this in a mo.
#
# Note that the stack defined here has a run image of ubi minimal, _without_ java.
cat builder-templates/template.builder.toml | envsubst '$REGISTRY_HOST $IMG_TAG'  > ${OUTPUT_DIR}/builder.toml

# Create the dockerfile for the java run image, in this case just ubi java, with env vars 
# and uid/gid set for use as a CNB run image.
# This is the image that will be used for java staged applications
cat builder-templates/template.Dockerfile.run-java-image | envsubst '$REGISTRY_HOST $IMG_TAG' > ${OUTPUT_DIR}/Dockerfile.run-java-image

# Create the dockerfile for the nodejs run image, in this case just ubi nodejs, with env vars 
# and uid/gid set for use as a CNB run image.
# This is the image that will be used for nodejs staged applications
cat builder-templates/template.Dockerfile.run-nodejs-image | envsubst '$REGISTRY_HOST $IMG_TAG' > ${OUTPUT_DIR}/Dockerfile.run-nodejs-image

# Create the dockerfile for the base run image, in this case just ubi minimal, with env vars 
# and uid/gid set for use as a CNB run image.
# This image should never be used.. but has to be present as part of the 'stack'
cat builder-templates/template.Dockerfile.run-stack-image | envsubst '$REGISTRY_HOST $IMG_TAG' > ${OUTPUT_DIR}/Dockerfile.run-stack-image

# Create the dockerfile for the base build image, this is the image that will be used
# by pack as the base for the builder image. 
# In this case, we're using ubi minimal + env vars & uid/gid customization.
cat builder-templates/template.Dockerfile.build-image | envsubst '$REGISTRY_HOST $IMG_TAG' > ${OUTPUT_DIR}/Dockerfile.build-image

# Clean up if we've built these before.
echo -e "\n>>>>>>>>>> Removing old build/run image...\n(Errors are fine if you haven't built these images before)"
docker image rm $REGISTRY_HOST/builder-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-stack:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-java:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-nodejs:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/builder:${IMG_TAG} --force

# Patch the java run img tag into the generate script, so the run.Dockerfile
# can be generated with the name of the run image we're defining in this script.
echo -e "\n>>>>>>>>>> Patching generate script with image tag..."
sed -i "s#^FROM localhost:5000/run-java:.*#FROM localhost:5000/run-java:${IMG_TAG}#" extensions/redhat-runtimes_java/0.0.1/bin/generate
sed -i "s#^FROM localhost:5000/run-nodejs:.*#FROM localhost:5000/run-nodejs:${IMG_TAG}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed -i "s#^CNB_USER_ID=.*#CNB_USER_ID=${CNB_USER_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed -i "s#^CNB_GROUP_ID=.*#CNB_GROUP_ID=${CNB_GROUP_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate

# Use docker to create the images for builder-base & run. 
echo -e "\n>>>>>>>>>> Building build base image..."
docker build . -t $REGISTRY_HOST/builder-base:${IMG_TAG} --target base -f ${OUTPUT_DIR}/Dockerfile.build-image 
echo -e "\n>>>>>>>>>> Building run stack image..."
docker build . -t $REGISTRY_HOST/run-stack:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-stack-image
echo -e "\n>>>>>>>>>> Building run java image..."
docker build . -t $REGISTRY_HOST/run-java:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-java-image
echo -e "\n>>>>>>>>>> Building run nodejs image..."
docker build . -t $REGISTRY_HOST/run-nodejs:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-nodejs-image

# Use pack to consume the buider-base and output a viable builder image.
echo -e "\n>>>>>>>>>> Pack creating builder image...\n  Using pack : ${PACK}"
$PACK config experimental true
$PACK builder create $REGISTRY_HOST/builder:${IMG_TAG} --config ${OUTPUT_DIR}/builder.toml

if [[ $? -ne 0 ]]; then
  echo -e "\n pack did not report success creating builder." >&2
  exit 1
fi

# Send all the currently built stuff off to the registry.
echo -e "\n>>>>>>>>>> Pushing all built images to registry"
docker push $REGISTRY_HOST/builder-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-stack:${IMG_TAG}
docker push $REGISTRY_HOST/run-java:${IMG_TAG}
docker push $REGISTRY_HOST/run-nodejs:${IMG_TAG}
docker push $REGISTRY_HOST/builder:${IMG_TAG}

echo -e "\n>>>>>>>>>> Build complete. Builder image : $REGISTRY_HOST/builder:${IMG_TAG}"



