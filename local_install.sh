#!/bin/bash

# Script to install or clean the labquote Typst package locally

PACKAGE_NAME="labquote"
PACKAGE_VERSION="0.1.0"
LOCAL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/typst/packages/preview/$PACKAGE_NAME/$PACKAGE_VERSION"
FILES="typst.toml lib.typ README.md LICENSE template"

# Function to install the package
install_package() {
    echo "Installing $PACKAGE_NAME v$PACKAGE_VERSION to $LOCAL_DIR"
    mkdir -p "$LOCAL_DIR"
    cp -r $FILES "$LOCAL_DIR/"
    echo "Installation complete"
}

# Function to clean the package
clean_package() {
    echo "Removing $PACKAGE_NAME v$PACKAGE_VERSION from $LOCAL_DIR"
    rm -rf "$LOCAL_DIR"
    echo "Cleanup complete"
}

# Check command-line argument
case "$1" in
    install)
        install_package
        ;;
    clean)
        clean_package
        ;;
    *)
        echo "Usage: $0 {install|clean}"
        exit 1
        ;;
esac
