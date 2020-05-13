#!/bin/bash
set -e
set -x

git clone https://github.com/appcircleio/appcircle-sample-android.git

mkdir temp-dir
touch temp-dir/metadata.json

export AC_REPOSITORY_DIR=./appcircle-sample-android
export AC_PLATFORM_TYPE=JavaKotlin
export AC_METADATA_OUTPUT_PATH=./metadata.json
export AC_TEMP_DIR=./temp-dir

ruby main.rb
