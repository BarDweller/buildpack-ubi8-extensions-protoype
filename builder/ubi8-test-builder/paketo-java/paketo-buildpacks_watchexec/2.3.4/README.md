# `gcr.io/paketo-buildpacks/watchexec`

The Paketo Watchexec Buildpack is a Cloud Native Buildpack that provides the Watchexec binary tool to support reloadable processes.

## Behavior

This buildpack will participate all the following conditions are met

* Another buildpack requires `watchexec`

The buildpack will do the following:

* Contributes Watchexec to a layer marked `launch` with command on `$PATH`

## License

This buildpack is released under version 2.0 of the [Apache License][a].

[a]: http://www.apache.org/licenses/LICENSE-2.0
