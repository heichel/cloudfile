#! /usr/bin/env sh

echo "Checking for build directory..."

if [ -d build ] ; then
	echo "build directory already exists."
	echo "Removing..."
	rm -rf ./build
fi

echo "Creating build directory"
mkdir build

echo "Moving into build directory"
cd ./build

echo "Generating build environment..."
cmake ..

echo "Making..."
cmake --build .
