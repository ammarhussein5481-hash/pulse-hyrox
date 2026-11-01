#!/bin/sh
# Build Pulse HYROX without installing the SDK on the host: a stock Java container runs the Connect IQ compiler.
#   SDK=/path/to/connectiq-sdk-lin-x.y.z  DEVICES=~/.Garmin/ConnectIQ/Devices  KEY=/path/to/developer_key.der  ./build.sh [device]
# No argument → store package (PulseHyrox.iq, release, every product in manifest.xml). With a device id → sideload build (PulseHyrox.prg).
set -e
SDK=${SDK:?set SDK to the unpacked Connect IQ SDK folder}; DEVICES=${DEVICES:-$HOME/.Garmin/ConnectIQ/Devices}; KEY=${KEY:?set KEY to your developer key (.der)}
mkdir -p bin
if [ -n "$1" ]; then
  docker run --rm -v "$SDK":/sdk -v "$DEVICES":/root/.Garmin/ConnectIQ/Devices -v "$KEY":/key.der -v "$PWD":/src -w /src eclipse-temurin:17-jre \
    java -jar /sdk/bin/monkeybrains.jar -o bin/PulseHyrox.prg -f monkey.jungle -d "$1" -y /key.der -w
else
  docker run --rm -v "$SDK":/sdk -v "$DEVICES":/root/.Garmin/ConnectIQ/Devices -v "$KEY":/key.der -v "$PWD":/src -w /src eclipse-temurin:17-jre \
    java -jar /sdk/bin/monkeybrains.jar -e -r -o bin/PulseHyrox.iq -f monkey.jungle -y /key.der -w
fi
ls -la bin/
