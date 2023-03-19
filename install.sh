#!/bin/bash
set -e

# Install system dependencies
brew install python@3.10 portaudio

# Install Python packages
pip3 install -r requirements.txt

# Set up shell alias
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "alias whisperer='sh $DIR/run.sh'" >> ~/.zshrc

echo ""
echo "Installation complete."
echo "Next: run ./install_whispercpp.sh to build whisper.cpp and download models."
echo ""
echo "IMPORTANT: Grant your terminal Accessibility and Input Monitoring permissions"
echo "in System Settings > Privacy & Security."
