#!/bin/bash

# Helps you install a font from a zip file URL. Usage:
# /helpers/install-font.sh <url-to-zip-file>

# Check if the URL is provided
if [ -z "$1" ]; then
  echo "Please provide a URL to a font zip file."
  exit 1
fi

# Create a temporary directory
TEMP_DIR=$(mktemp -d)

# Download the font zip file
wget -O "$TEMP_DIR/font.zip" "$1"

# Unzip the font file
unzip "$TEMP_DIR/font.zip" -d "$TEMP_DIR"

# Move the font files to the system fonts directory
sudo mv "$TEMP_DIR"/*.{ttf,otf} /usr/local/share/fonts/

# Update the font cache
fc-cache -f -v

# Clean up
rm -rf "$TEMP_DIR"

echo "Font installed successfully!"