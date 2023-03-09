#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo -e "Usage: build.sh image-tag registry-host\neg. build.sh my-image localhost:5000" >&2
  exit 2
fi

# Args 
export IMG_TAG=$1
export REGISTRY_HOST=$2

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
   # determine OS.. 
   case "$OSTYPE" in
     darwin*)  
       if [[ $(uname -m) == 'arm64' ]]; then 
         packurl="https://github.com/buildpacks/pack/releases/download/v0.29.0-rc1/pack-v0.29.0-rc1-macos-arm64.tgz"
       else
         packurl="https://github.com/buildpacks/pack/releases/download/v0.29.0-rc1/pack-v0.29.0-rc1-macos.tgz"
       fi
       ;; 
     linux*)   
       if [[ $(uname -m) == 'arm64' ]]; then 
         packurl="https://github.com/buildpacks/pack/releases/download/v0.29.0-rc1/pack-v0.29.0-rc1-linux-arm64.tgz"
       else
         packurl="https://github.com/buildpacks/pack/releases/download/v0.29.0-rc1/pack-v0.29.0-rc1-linux.tgz"
       fi
       ;;
     *)        
       echo "Unknown OS: $OSTYPE, you will need to download pack cli and place it in ${OUTPUT_DIR}/bin" 
       ;;
   esac
   echo "  - Obtaining pack from $url"
   curl -sSL "${packurl}" | tar -C ${OUTPUT_DIR}/bin --no-same-owner -xz pack
   echo "  - Setting execute bit"
   chmod +x ${OUTPUT_DIR}/bin/pack
   echo "  - pack obtained."
else
   echo -e "  - found, using pack"
fi


echo -e "\n>>>>>>>>>> Creating build artifacts from templates"
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

# Patch the java run img tag into the generate script, so the run.Dockerfile
# can be generated with the name of the run image we're defining in this script.
echo -e "\n>>>>>>>>>> Patching generate scripts with image tag..."
# Mac os built in sed is incompatible with linux sed -i flag. 
sedi=(-i)
case "$(uname)" in
  # For macOS, use two parameters
  Darwin*) sedi=(-i "")
esac
sed "${sedi[@]}" -e "s#^FROM localhost:5000/run-java:.*#FROM localhost:5000/run-java:${IMG_TAG}#" extensions/redhat-runtimes_java/0.0.1/bin/generate
sed "${sedi[@]}" -e "s#^FROM localhost:5000/run-nodejs:.*#FROM localhost:5000/run-nodejs:${IMG_TAG}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed "${sedi[@]}" -e "s#^CNB_USER_ID=.*#CNB_USER_ID=${CNB_USER_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate
sed "${sedi[@]}" -e "s#^CNB_GROUP_ID=.*#CNB_GROUP_ID=${CNB_GROUP_ID}#" extensions/redhat-runtimes_nodejs/0.0.1/bin/generate

# Clean up if we've built these before.
echo -e "\n>>>>>>>>>> Removing old build/run image...\n(Errors are fine if you haven't built these images before)"
docker image rm $REGISTRY_HOST/builder-base:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-stack:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-java:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/run-nodejs:${IMG_TAG} --force
docker image rm $REGISTRY_HOST/builder:${IMG_TAG} --force

# Use docker to create the images for builder-base & run. 
echo -e "\n>>>>>>>>>> Building build base image..."
docker build . -t $REGISTRY_HOST/builder-base:${IMG_TAG} --target base -f ${OUTPUT_DIR}/Dockerfile.build-image 
if [[ $? -ne 0 ]]; then
  echo -e "\n failed to create builder base image." >&2
  exit 1
fi
echo -e "\n>>>>>>>>>> Building run stack image..."
docker build . -t $REGISTRY_HOST/run-stack:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-stack-image
if [[ $? -ne 0 ]]; then
  echo -e "\n failed to create run stack image." >&2
  exit 1
fi
echo -e "\n>>>>>>>>>> Building run java image..."
docker build . -t $REGISTRY_HOST/run-java:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-java-image
if [[ $? -ne 0 ]]; then
  echo -e "\n failed to create run java image." >&2
  exit 1
fi
echo -e "\n>>>>>>>>>> Building run nodejs image..."
docker build . -t $REGISTRY_HOST/run-nodejs:${IMG_TAG} --target run -f ${OUTPUT_DIR}/Dockerfile.run-nodejs-image
if [[ $? -ne 0 ]]; then
  echo -e "\n failed to create run nodejs image." >&2
  exit 1
fi

# Send all the currently built stuff off to the registry.
echo -e "\n>>>>>>>>>> Pushing all built images to registry"
docker push $REGISTRY_HOST/builder-base:${IMG_TAG}
docker push $REGISTRY_HOST/run-stack:${IMG_TAG}
docker push $REGISTRY_HOST/run-java:${IMG_TAG}
docker push $REGISTRY_HOST/run-nodejs:${IMG_TAG}

# Use pack to consume the buider-base and output a viable builder image.
echo -e "\n>>>>>>>>>> Pack creating builder image...\n  Using pack : ${PACK}"
$PACK config experimental true
$PACK builder create $REGISTRY_HOST/builder:${IMG_TAG} --config ${OUTPUT_DIR}/builder.toml

if [[ $? -ne 0 ]]; then
  echo -e "\nError: pack did not report success creating builder." >&2
  exit 1
fi

# Push final image to registry
echo -e "\n>>>>>>>>>> Pushing builder image to registry"
docker push $REGISTRY_HOST/builder:${IMG_TAG}

echo -e "\n>>>>>>>>>> Build complete. Builder image : $REGISTRY_HOST/builder:${IMG_TAG}"



