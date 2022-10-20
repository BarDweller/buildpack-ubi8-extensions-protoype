# UBI8 Builder Image

**Note: _you probably want to be looking at `..\ubi8-test-builder-via-pack`. This folder contains an approach used during development, that is no longer required._**

## Overview
A hack script to produce builder based on a UBI base image, that will use an extension to install Java, and Paketo to build the app.

This approach to creating a build is **NOT RECOMMENDED** but was required during development before the `pack cli` was able to generate builder images with extensions. It is preserved here for reference purposes only.

## Building

Invoke the buildscript with the tag, registry, and lifecycle image it should use. 
Lifecycle images are created from lifecycle build archives in the `..\lifecycle` folder. This staged approach was used during development of extension support, when there was no published lifecycle available with extension support.

`./build.sh <buildertag> <registry> lifecycle:local-latest`

eg, 

`/build.sh testbuilder localhost:5000 lifecycle:local-latest`

