Simple little dir to allow conversion of a selected lifecycle build archive into a docker image containing the content in /lifecycle

The docker image is then used by the Builder modification multi-stage build to apply the lifecycle to the builder.

Select the lifecycle archive name using env var LIFECYCLE_ARCHIVE if unset, it will match the most recent lifecycle archive in the directory.
