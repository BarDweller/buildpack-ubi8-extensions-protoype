# UBI8 Builder Image

## Overview
A simple builder based on a UBI base image, using an extension to install Java, and Paketo to build the app.

The build process for this builder is using a pre-release version of the pack cli, that must be compiled, via
the `build.sh` in the `../prototype-pack` directory. 

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

The builder image created via this folder can be used via the bash_platform, or via the pre-release pack cli. 

### Pack Cli

To drive the builder via pack, you can use a command similar to this.

`../prototype-pack/pack/out/pack build testapp --builder localhost:5000/builder:testbuilder --path ../../bash-platform/sample-springboot-java-app --network host -v`

- `--builder` to reference the builder created above
- `--path` to point at a folder with a project to be built 
- `--network` host if you are using a registry at localhost 
  _(because otherwise when the build process attempts to access the registry at 'localhost' inside its container, it will fail as localhost is different in that context)_
- `-v` to enable verbose output, in case it fails to have some context =)

### Bash Platform

The bash platform is a minimal implementation of the buildpacks platform spec, and can be used to drive builds with builder images that use extensions. It can be useful as it is easy to follow & modify each step if required.

### Run build with builder image
- from this folder `cd ../../bash-platform` to switch to the `bash-platform` directory.
- `./run_build.sh -b builder:testbuilder -r localhost:5000 -w ./sample-springboot-java-app -a testapp -d info` 
  - -b is the builder image to use. 
  - -r the registry, 
  - -w the workspace to build 
  - -a the name for the produced app
  - -d the log level.

## Technical Overview

`build.sh` is designed as a self contained script that will:
- generate the `builder.toml` that will be used by pack
- create dockerfiles for the builder base image, minimal run image, and java run image
- patch the `generate` script in the contained extension to reference the java run image being created
- use `docker` to create images from the generated dockerfiles
- use the pre-release `pack` cli to generate a builder image with the extensions in
- push all the images to a registry.

