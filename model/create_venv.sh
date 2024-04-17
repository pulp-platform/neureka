#!/bin/bash

python -m pip install --user virtualenv
python -m virtualenv venv
source venv/bin/activate
python -m pip install torch>=1.11 --extra-index-url https://download.pytorch.org/whl/cpu
python -m pip install -r model/requirements.txt
