#!/bin/bash

if [ -z "${LIFECYCLE_ARCHIVE}" ]; then 
  LIFECYCLE_ARCHIVE=`ls -t lifecycle-v* | head -n 1`
fi

echo Selected Archive : ${LIFECYCLE_ARCHIVE}

rm -rf lifecyclei-target
mkdir lifecycle-target
cd lifecycle-target
tar -xzvf ../${LIFECYCLE_ARCHIVE}
cp ../Dockerfile .
docker build -t lifecycle:local-latest .
cd ..
