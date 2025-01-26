#!/usr/bin/env bash
set -e

if [ "$1" == "--embed" ]; then
    # Compile fastPathSign
    pushd TrollStore/Exploits/fastPathSign
    make
    popd
fi

xcodebuild -configuration Release -derivedDataPath DerivedData/ValidationRelay -destination 'generic/platform=iOS' -scheme ValidationRelay CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY=""

if [ "$1" == "--embed" ]; then
    ./TrollStore/Exploits/fastPathSign/fastPathSign --entitlements ValidationRelay/ValidationRelay.entitlements DerivedData/ValidationRelay/Build/Products/Release-iphoneos/ValidationRelay.app/ValidationRelay 
    cp DerivedData/ValidationRelay/Build/Products/Release-iphoneos/ValidationRelay.app/ValidationRelay EmbeddedValidationRelay
else
    ldid -SValidationRelay/ValidationRelay.entitlements -Idev.jjtech.experiments.ValidationRelay DerivedData/ValidationRelay/Build/Products/Release-iphoneos/ValidationRelay.app/ValidationRelay

    pushd DerivedData/ValidationRelay/Build/Products/Release-iphoneos
    rm -rf Payload ValidationRelay.ipa
    mkdir Payload
    cp -r ValidationRelay.app Payload
    zip -qry ValidationRelay.tipa Payload
    popd
    cp DerivedData/ValidationRelay/Build/Products/Release-iphoneos/ValidationRelay.tipa .
    rm -rf Payload
    open -R ValidationRelay.tipa
fi
