#!/usr/bin/env bash

# Detect the operating system
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux"
    bash <(curl -sSL "https://raw.githubusercontent.com/siddharthjain25/pocket/main/scripts/run.sh")
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "Detected Windows"
    powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/siddharthjain25/pocket/main/scripts/run.ps1' -OutFile $env:TEMP\pocket-key-run.ps1; & $env:TEMP\pocket-key-run.ps1"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    # Add your macOS script here if needed
fi
