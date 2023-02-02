# UBI8 Builder Image

## Overview
A simple builder based on a UBI base image, using an extension to install Java, and Paketo to build the app.

## Prereqs

Using extensions requires use of a docker registry. For the purpose of testing, it is sufficient to use a local docker registry, avoiding credential management challenges for now ;)

You can run a local docker registry with 

`docker run -d -p 5000:5000 --restart=always --name registry registry:2`

## Building

The builder image will be created with the name `builder` and the tag specified as the first argument, and 
the resulting image will be pushed to the registry specified as the second argument.

The builder image is created using the build script passing the tag & registry as 

`./build.sh <buildertag> <registry>`

eg, 

`/build.sh testbuilder localhost:5000`

## Usage

To drive the builder via pack, you can use a command similar to this.

`./build-artifacts/bin/pack build testapp --builder localhost:5000/builder:testbuilder --path test-applications/sample-springboot-java-app --network host -v`

- `--builder` to reference the builder created above
- `--path` to point at a folder with a project to be built 
- `--network` host if you are using a registry at localhost 
  _(because otherwise when the build process attempts to access the registry at 'localhost' inside its container, it will fail as localhost is different in that context)_
- `-v` to enable verbose output, in case it fails to have some context =)


## Technical Overview

`build.sh` is designed as a self contained script that will:
- generate from a template, the `builder.toml` that will be used by pack, and the dockerfiles for the builder base image, minimal run image, and nodejs & java run images
  - Templates are used to patch in the image names (derived from the image tag script argument) into appropriate places.
- patch the `generate` script in the contained extensions to reference the appropriate run images
- use `docker` to create images from the generated dockerfiles
- use the `pack` cli to generate a builder image containing the extensions and associated paketo buildpacks
- push all the images to a registry.


## Notes

If you are looking for the bash-platform implementation that used to be within this repo, it has moved to https://github.com/BarDweller/buildpack-platform-bash

