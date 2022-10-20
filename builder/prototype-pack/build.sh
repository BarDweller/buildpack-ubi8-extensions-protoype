#!/bin/bash

echo "Testing for Go"
go version
RC=$?
if [[ RC -ne 0 ]]; then
    echo "Go not found.. checking usr/local"
    if [ -d /usr/local/go ]; then
        PATH=$PATH:/usr/local/go
    else
        echo "Go not found, please install go >= 1.19"
    fi
fi

if [ -d pack ]; then 
    echo "Using existing pack source, delete pack directory to refresh"
else
    echo "Cloning pack repo to pack directory"
    git clone https://github.com/buildpacks/pack pack
fi

cd pack
echo "Switching to defined commit (placeholder until pack release)"
git checkout d4d029fc3592946be049434bf0cd6b06dce478a8
echo "Building pack"
make build



