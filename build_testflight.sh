#!/usr/bin/env bash

set -e

APP_NAME=ValidationRelay\ TestFlight
xcodebuild -configuration Release -derivedDataPath DerivedData/ValidationRelay -destination 'generic/platform=iOS' -scheme "ValidationRelay TestFlight" CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY=""
ldid -SValidationRelay/ValidationRelay.entitlements -Icom.apple.TestFlight "DerivedData/ValidationRelay/Build/Products/Release-iphoneos/$APP_NAME.app/$APP_NAME"
ldid -STestFlightServiceExtension/TestFlightServiceExtension.entitlements -Icom.apple.TestFlight.ServiceExtension "DerivedData/ValidationRelay/Build/Products/Release-iphoneos/$APP_NAME.app/PlugIns/TestFlightServiceExtension.appex/TestFlightServiceExtension"
echo signed.
pushd DerivedData/ValidationRelay/Build/Products/Release-iphoneos
rm -rf Payload "$APP_NAME.ipa"
mkdir Payload
cp -r "$APP_NAME.app" Payload
zip -qry "$APP_NAME.tipa" Payload
popd
cp "DerivedData/ValidationRelay/Build/Products/Release-iphoneos/$APP_NAME.tipa" .
rm -rf Payload
open -R "$APP_NAME.tipa"
