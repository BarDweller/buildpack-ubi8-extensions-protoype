# A simple test project

This project is designed to allow containerised build testing with developer builds of quarkus. 

## Why?

If you build quarkus locally, you end up with quarkus as version 999-SNAPSHOT in your local maven repo. You can then use this version of quarkus with test projects to try out your updates to quarkus. This all works fine locally, but if you are trying to test aspects of the quarkus build, that will be run within a container, then your custom 999-SNAPSHOT version of quarkus will not be know to the maven instance running inside the container, and the build inside will fail. 

## How?

This project uses maven profiles, to allow selection of the 999-SNAPSHOT level of quarkus only when `-Ddevbuild=true` is passed to maven. This way the local build can be told to use the development build, while the in-container build will use the release build. Because the development build is only needed to initiate the container image build, this allows the application to build as expected. 

## What?

`./mvnw clean package -Dquarkus.container-image.build=true -Ddevbuild=true`

