A simple builder based on a UBI base image, using an extension to install Java, and Paketo to build the app.

./build.sh <buildertag> <registry> lifecycle:local-latest

eg, 

/build.sh testbuilder localhost:5000 lifecycle:local-latest

