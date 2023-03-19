#!/bin/bash

git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make
cd models
bash ./download-ggml-model.sh tiny.en
bash ./download-ggml-model.sh small.en
bash ./download-ggml-model.sh base.en
bash ./download-ggml-model.sh medium.en
