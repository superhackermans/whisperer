#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Install system dependencies
brew install python@3.10 portaudio

# Install Python packages
pip3 install -r "$REPO_ROOT/requirements.txt"

# Set up shell alias
echo "alias whisperer='sh $SCRIPT_DIR/run.sh'" >> ~/.zshrc

echo ""
echo "Installation complete."
echo "Next: run ./scripts/install_whispercpp.sh to build whisper.cpp and download models."
echo ""
echo "IMPORTANT: Grant your terminal Accessibility and Input Monitoring permissions"
echo "in System Settings > Privacy & Security."
