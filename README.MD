# Lifecycle test project

A quick bunch of bash scripts to build;
 - an image containing a lifecycle
 - a builder image with the updated lifecycle, and extension example
 - an app image using the builder image

## Usage

### Generate local lifecycle image
- Download a lifecycle artifact (lifecyle-linux-x86-64) from a build. 
- Unzip it to obtain the .tgz file `lifecycle-v*.x86-64.tgz`
- Plase the .tgz archive into `lifecycle-archives`
- `cd lifecycle-archives`
- `./make-lifecycle-image.sh` (or `LIFECYCLE_ARCHIVE=filename ./make-lifecycle-image.sh` to select tgz manually)

### Generate local builder image
- from the project root, `cd builder/<buildername>`
- run `./build.sh nameforbuilder localhost:5000 lifecycle:local-latest` (1st arg is used in the tag to identify the images built, 2nd arg is registry to push to, last arg is id of lifeycle image to update lifecyle from)
- builder image is published as `builder:nameforbuilder`

### Run build with builder image
- from the project root, `cd bash-platform`
- `./run_build.sh -b builder:buildername -r localhost:5000 -w ./sample-java-app -a testapp -d info` -b is the builder image to use. -r the registry, -w the workspace to build -a the name for the produced app, and -d the log level.

