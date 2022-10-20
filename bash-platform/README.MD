# Bash Platform Implementation

## Overview
A very optimistic implementation of the Buildpacks Platform spec using Bash. 

Do not expect great things ;) 

This is just enough to invoke lifecycle phases with the appropriate volumes mounted. It handles the basics of pulling the builder image, retrieving the user/group ids for the build, deleting/recreating cache volumes used during the build, and prepopulating the appropriate volume with the designated project. Along with some minor fixes found to be required along the way. 

It tolerates a docker registry running at localhost by running each lifecycle phase as a container on the host network. 

All containers should automatically clean up after themselves. 

## Usage

Drive the `./build.sh` script with the following arguments.. 

- `-b` builder image name (eg, `builder:testbuilder`)
- `-r` the registry to use (builder image is expected to be found here, and app image will be pushed here, eg, `localhost:5000`)
- `-w` the workspace folder to build (eg, the java/node project folder)
- `-d` the debug level for output (eg, `info` or `debug`)
- `-a` the name to use for the created app image (eg. `appname`)

