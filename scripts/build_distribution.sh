#!/bin/sh
#
# Copyright 2004-present Facebook. All Rights Reserved.
#

# This script builds the FBiOSSDK.framework that is distributed at
# https://github.com/facebook/facebook-ios-sdk/downloads/FBiOSSDK.framework.zip

. ${FB_SDK_SCRIPT:-$(dirname $0)}/common.sh
test -x "$PACKAGEMAKER" || die 'Could not find packagemaker in $PATH'

FB_SDK_PKG=$FB_SDK_BUILD/FacebookSDK-${FB_SDK_VERSION_FULL}.pkg
FB_SDK_FRAMEWORK_TGZ=${FB_SDK_FRAMEWORK}-${FB_SDK_VERSION_FULL}.tgz

FB_SDK_BUILD_PACKAGE=$FB_SDK_BUILD/package
FB_SDK_BUILD_PACKAGE_TEMPLATES=$FB_SDK_BUILD_PACKAGE/Library/Developer/XCode/Templates/FacebookSDK
FB_SDK_BUILD_PACKAGE_FRAMEWORK_SUBDIR=Documents/FacebookSDK
FB_SDK_BUILD_PACKAGE_FRAMEWORK=$FB_SDK_BUILD_PACKAGE/$FB_SDK_BUILD_PACKAGE_FRAMEWORK_SUBDIR
FB_SDK_BUILD_PACKAGE_SAMPLES=$FB_SDK_BUILD_PACKAGE/Documents/FacebookSDK/Samples
FB_SDK_BUILD_PACKAGE_DOCS=$FB_SDK_BUILD_PACKAGE/Documents/FacebookSDK/Documentation

# -----------------------------------------------------------------------------
# Call out to build prerequisites.
#
if is_outermost_build; then
    . $FB_SDK_SCRIPT/build_framework.sh
    . $FB_SDK_SCRIPT/build_documentation.sh
fi
echo Building Distribution.

# -----------------------------------------------------------------------------
# Compress framework for standalone distribution
#
echo "Compressing framework for standalone distribution."
\rm -rf ${FB_SDK_FRAMEWORK_TGZ}

# Current directory matters to tar.
cd $FB_SDK_BUILD || die "Could not cd to $FB_SDK_BUILD"
tar -c -z $FB_SDK_FRAMEWORK_NAME >  $FB_SDK_FRAMEWORK_TGZ \
  || die "tar failed to create ${FB_SDK_FRAMEWORK_NAME}.tgz"

# -----------------------------------------------------------------------------
# Build package directory structure
#
echo "Building package directory structure."
\rm -rf $FB_SDK_BUILD_PACKAGE
mkdir $FB_SDK_BUILD_PACKAGE \
  || die "Could not create directory $FB_SDK_BUILD_PACKAGE"
mkdir -p $FB_SDK_BUILD_PACKAGE_TEMPLATES
mkdir -p $FB_SDK_BUILD_PACKAGE_FRAMEWORK
mkdir -p $FB_SDK_BUILD_PACKAGE_SAMPLES
mkdir -p $FB_SDK_BUILD_PACKAGE_DOCS

\cp -r $FB_SDK_TEMPLATES/* $FB_SDK_BUILD_PACKAGE_TEMPLATES \
  || die "Could not copy $FB_SDK_TEMPLATES"
\cp -R $FB_SDK_FRAMEWORK $FB_SDK_BUILD_PACKAGE_FRAMEWORK \
  || die "Could not copy $FB_SDK_FRAMEWORK"
\cp -R $FB_SDK_SAMPLES/ $FB_SDK_BUILD_PACKAGE_SAMPLES \
  || die "Could not copy $FB_SDK_BUILD_PACKAGE_SAMPLES"
\cp -R $FB_SDK_FRAMEWORK_DOCS/ $FB_SDK_BUILD_PACKAGE_DOCS \
  || die "Could not copy $$FB_SDK_FRAMEWORK_DOCS"
\cp $FB_SDK_ROOT/README.mdown $FB_SDK_BUILD_PACKAGE/Documents/FacebookSDK \
  || die "Could not copy README.mdown"

# -----------------------------------------------------------------------------
# Fixup projects to point to the SDK framework
#
for fname in $(find $FB_SDK_BUILD_PACKAGE_SAMPLES -name "project.pbxproj" -print); do \
  sed "s|../../build|../../../../${FB_SDK_BUILD_PACKAGE_FRAMEWORK_SUBDIR}|g" \
    ${fname} > ${fname}.tmpfile  && mv ${fname}.tmpfile ${fname}; \
done

# -----------------------------------------------------------------------------
# Build .pkg from package directory
#
echo "Building .pkg from package directory."
\rm -rf $FB_SDK_PKG
$PACKAGEMAKER \
  --doc $FB_SDK_SRC/Package/FBiOSSDK.pmdoc \
  --domain user \
  --target 10.5 \
  --version $FB_SDK_VERSION \
  --out $FB_SDK_PKG \
  --title 'Facebook iOS SDK' \
  || die "PackageMaker reported error"

# -----------------------------------------------------------------------------
# Done
#
echo "Successfully built SDK distribution:"
echo "  $FB_SDK_FRAMEWORK_TGZ"
echo "  $FB_SDK_PKG"
common_success