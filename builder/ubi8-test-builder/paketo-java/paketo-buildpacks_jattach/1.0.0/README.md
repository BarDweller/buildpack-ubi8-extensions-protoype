# `gcr.io/paketo-buildpacks/jattach`

The Paketo JAttach Buildpack is a Cloud Native Buildpack that provides the [JAttach binary](https://github.com/apangin/jattach) to send commands to a remote JVM via Dynamic Attach mechanism.

## Behavior

This buildpack will participate all the following conditions are met

* `$BP_JATTACH_ENABLED` is set

The buildpack will do the following:

* Contributes JAttach to a layer marked `launch` with command on `$PATH`

## License

This buildpack is released under version 2.0 of the [Apache License][a].

[a]: http://www.apache.org/licenses/LICENSE-2.0
