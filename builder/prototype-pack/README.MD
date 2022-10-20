# PreRelease Pack with Extension Support

## Overview

This folder contains a convenience script to build a local copy of a version of the pack cli that understands extensions. 

Once a version of the pack cli is released containing this support, this folder will no longer be required. 

## Prereqs

You will need the following installed and on the path

- `Go` version >= 1.19
- `git`
- `make`

## Building

Invoke the `build.sh` it will pull the pack source, and build the commit that has 
been tested as working. The resulting binary is created at the path `.\pack\out\pack`. Other scripts will expect to find it there. 
