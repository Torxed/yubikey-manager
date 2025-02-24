#!/bin/bash
# Script to produce a signed OS X installer .pkg

set -e

if [ "$#" -lt 2 ]; then
    echo ""
    echo "      Usage: ./make_release.sh <apple_account> <apple_password>"
    echo ""
    exit 0
fi

CWD=`pwd`
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
echo "Script dir: $SCRIPT_DIR"

SOURCE_DIR="$CWD/ykman"

# Ensure executable, since we may have unpacked from zip
chmod +x $SOURCE_DIR/ykman

RELEASE_VERSION=`$SOURCE_DIR/ykman --version | awk '{print $(NF)}'`
PKG="yubikey-manager-$RELEASE_VERSION-mac.pkg"

echo "This will sign and notarize the app. Please make sure you have the code signing YubiKey connected."
echo ""
echo "Release version: $RELEASE_VERSION"
echo "Binaries: $SOURCE_DIR"
echo "Apple user ID for notarization: $1"
echo ""
read -p "Press enter to continue..."

# Sign binaries
codesign -f --timestamp --options runtime --entitlements $SCRIPT_DIR/ykman.entitlements --sign 'Application' $SOURCE_DIR/ykman
codesign -f --timestamp --options runtime --sign 'Application' $(find $SOURCE_DIR -name "*.dylib" -o -name "*.so")
codesign -f --timestamp --options runtime --sign 'Application' $SOURCE_DIR/Python

# Build pkg
sh $SCRIPT_DIR/make_pkg.sh ykman-unsigned.pkg

# Sign the installer
productsign --sign 'Installer' ykman-unsigned.pkg $PKG

# Clean up
rm ykman-unsigned.pkg

echo "Installer signed, submitting for Notarization..."

# Notarize
RES=$(xcrun altool -t osx -f "$PKG" --primary-bundle-id com.yubico.yubikey-manager --notarize-app -u $1 -p $2)
echo ${RES}
ERRORS=${RES:0:9}
if [ "$ERRORS" != "No errors" ]; then
	echo "Error uploading for notarization"
	exit
fi
UUID=${RES#*=}
STATUS=$(xcrun altool --notarization-info $UUID -u $1 -p $2)

while true
do
	if [[ "$STATUS" == *"in progress"* ]]; then
		echo "Notarization still in progress. Sleep 30s."
		sleep 30
		echo "Retrieving status again."
		STATUS=$(xcrun altool --notarization-info $UUID -u $1 -p $2)
	else
		echo "Status changed."
		break
	fi
done

echo "Notarization status: ${STATUS}"

if [[ "$STATUS" == *"success"* ]]; then
	echo "Notarization successfull. Staple the .pkg"
	xcrun stapler staple -v "$PKG"

	echo "# .pkg stapled. Everything should be ready for release!"
fi
