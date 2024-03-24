#!/usr/bin/env bash

set -e

xcodebuild -configuration Release -derivedDataPath DerivedData/ValidationRelay -destination 'generic/platform=iOS' -scheme ValidationRelay CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY=""
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
