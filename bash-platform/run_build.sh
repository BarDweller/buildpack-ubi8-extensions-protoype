# Bash Platform
# A very simple implementation of the Cloud Native Buildpacks Platform Spec.
# This is not intended to be a serious platform impl, but just enough to 
# allow driving of each phase from a bash prompt as a test environment. 


# Parse args using getopt.

set -e
set -o errexit -o pipefail -o noclobber -o nounset
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'getopt --test failure.'
    exit 1
fi

LONGOPTS=builder:,registry:,workspace:,debug:,appname:
OPTIONS=b:r:w:d:a:

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # opt parsing failure, msg emitted to stdout
    exit 2
fi
eval set -- "$PARSED"

BUILDER="unset"
REGISTRY_HOST="localhost:5000"
WORKSPACE="unset"
DEBUG="info"
APPNAME="appname"
while true; do
	case "$1" in
		-b|--builder)
			BUILDER="$2"
			shift 2;;
		-r|--registry)
			REGISTRY_HOST="$2"
			shift 2;;
		-w|--workspace)
			WORKSPACE="$2"
			shift 2;;
		-d|--debug)
			DEBUG="$2"
			shift 2;;
		-a|--appname)
			APPNAME="$2"
			shift 2;;
	        --)
			shift
			break;;
		*)
			echo "Bad arg $1"
			exit 3;;
	esac
done

# Setup some basic color choices for text

MAGENTA="\e[35m"
RED="\e[91m"
RESET="\e[0m"

# The platform api we'll pass as env to each phase.

CNB_PLATFORM_API=0.10

echo -e "$MAGENTA>>>>>>>>>> clearing/creating cache folders...$RESET"

# Currently we flush the entire cache for each build, might make this 
# into an option, but as the cache name isn't tied to the project being
# built, this is the simplest cache management for now.

# Note, it's pretty likely you'll need to sudo rm -rf ./target
# because kaniko will have vomited a pile of root owned files into the
# dir that mortals are not allowed to remove.

rm -rf ./target
mkdir -p ./target
mkdir -p ./target/layers
mkdir -p ./target/platform
mkdir -p ./target/kaniko

echo -e "$MAGENTA>>>>>>>>>> Cleanup old images$RESET"

# If we ever did build an image before, we'll remove it here, to ensure
# we end up with the new one. This is obviously less ideal if the build
# fails ;p 

docker image rm $REGISTRY_HOST/$APPNAME --force

echo -e "$MAGENTA>>>>>>>>>> Cloning workspace ...$RESET"

# The workspace dir is destructively modified during a build, so we 
# copy it to a new directory to simulate it being copied into a volume
# except without the hassle of actually copying it into a volume.

cp -rp $WORKSPACE ./target/workspace

echo -e "$MAGENTA>>>>>>>>>> Running analyser...$RESET"

# analyzer will look at an old app image, that we've already deleted
# oops, so this won't do anything fantastically useful at the mo.
# --network host is used because we are using localhost:5000 by 
# default as our 'registry', and usuall our localhost isn't the 
# containers localhost, so that falls apart.. but network host will
# fix that.. in a real scenario, the registry wouldn't be on localhost
# and thus the network host wouldn't be required.

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  -v $PWD/target/kaniko/:/kaniko \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  --user 0:0 \
  --network host \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/analyzer \
  -analyzed /layers/analyzed.toml \
  $REGISTRY_HOST/$APPNAME

echo -e "$MAGENTA>>>>>>>>>> Running detect...$RESET"

# detect phase runs the various detect scripts of extensions and
# dockerfiles to decide who will participate in the build. 
# it will also run the generate step for any participating extensions
# and place their output into the -generated location.
# (Note: currently you MUST set -generated, else a bad default
#        is used "<layers>")

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  --user 1000:1000 \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/detector \
  -layers /layers \
  -generated /layers/generated \
  -log-level $DEBUG

echo -e "$MAGENTA>>>>>>>>>> Running restore..$RESET"

# restore phase is used to prepopulate the kaniko cache, allowing
# the extender phase to execute kaniko without kaniko being exposed
# to registry credentials. 
# again here we are using --network host to allow localhost:5000 
# docker registry to work within the container.
# -build-image arg here is critical, as it tells this phase
# which builder image needs to be precached for potential extension
# by the extender phase next.

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  -v $PWD/target/kaniko/:/kaniko \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  --user 1000:1000 \
  --network host \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/restorer \
  -build-image $REGISTRY_HOST/$BUILDER \
  -log-level $DEBUG

echo -e "$MAGENTA>>>>>>>>>> Running extender...$RESET"

# Kaniko refers to the images by their Repo Digest, this is 
# a little hacky, but we ask docker to give us the first RepoDigest
# for the builder image we have been using, and then use that to form
# up the oci:/kaniko/cache/base/id reference that extender will 
# use to refer to the builder image. 
BUILDERHASH=$(docker inspect --format='{{index .RepoDigests 0}}' $REGISTRY_HOST/$BUILDER  | sed -e 's/^.*sha256:/sha256:/g' )

# Invoke the extender phase, passing the kaniko cache reference for the
# builder image, so it can be extended by any generated dockerfiles from
# extensions. 
# Path for generated is being set here as a precaution due to the bad
# default path encounted during detect phase.

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  -v $PWD/target/kaniko/:/kaniko \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  -e REGISTRY_HOST=$REGISTRY_HOST \
  --user 0:0 \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/extender \
  -generated /layers/generated \
  -log-level $DEBUG \
  -gid 1000 \
  -uid 1000 \
  oci:/kaniko/cache/base/$BUILDERHASH

echo -e "$MAGENTA>>>>>>>>>> Exporting final app image...$RESET"

# Lastly, run the export phase, again passing network host
# to allow it to talk to 'locahost:5000' as the registry host
# during this test run. 

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  --user 0:0 \
  --network host \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/exporter \
  -log-level debug \
  $REGISTRY_HOST/$APPNAME

# Pull the app back from the registry =)
docker pull $REGISTRY_HOST/$APPNAME

