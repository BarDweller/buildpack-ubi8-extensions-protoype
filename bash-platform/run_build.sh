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

MAGENTA="\e[35m"
RED="\e[91m"
RESET="\e[0m"

CNB_PLATFORM_API=0.10

echo -e "$MAGENTA>>>>>>>>>> clearing/creating cache folders...$RESET"

rm -rf ./target
mkdir -p ./target
mkdir -p ./target/layers
mkdir -p ./target/platform
mkdir -p ./target/kaniko

echo -e "$MAGENTA>>>>>>>>>> Cleanup old images$RESET"

docker image rm $REGISTRY_HOST/$APPNAME --force

echo -e "$MAGENTA>>>>>>>>>> Cloning workspace ...$RESET"
cp -rp $WORKSPACE ./target/workspace

echo -e "$MAGENTA>>>>>>>>>> Running detect...$RESET"

docker run \
  --privileged \
  -v $PWD/target/layers:/layers \
  -v $PWD/target/platform:/platform \
  -v $PWD/target/workspace:/workspace \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  --user 1000:1000 \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/detector \
  -layers /layers \
  -log-level $DEBUG

echo -e "$MAGENTA>>>>>>>>>> Running extender...$RESET"

docker run \
  --privileged \
  -v $PWD/target/layers/:/layers \
  -v $PWD/target/platform/:/platform \
  -v $PWD/target/workspace/:/workspace \
  -v $PWD/target/kaniko/:/kaniko \
  -e CNB_PLATFORM_API=${CNB_PLATFORM_API} \
  -e REGISTRY_HOST=$REGISTRY_HOST \
  --user 0:0 \
  --network host \
  $REGISTRY_HOST/$BUILDER \
  /cnb/lifecycle/extender \
  -app $APPNAME \
  -log-level $DEBUG

docker pull $REGISTRY_HOST/extended/buildimage

echo -e "$MAGENTA>>>>>>>>>> Exporting final app image...$RESET"

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

docker pull $REGISTRY_HOST/$APPNAME

