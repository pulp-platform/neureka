#!/bin/bash
# Copyright (C) 2020-2024 ETH Zurich and University of Bologna
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Francesco Conti (f.conti@unibo.it)
#

# Running this si
export N_PROC=4
export P_STALL=0.04
TIMEOUT=300

export PE_H=4
export PE_W=2

export MODE=1

# Declare a string array with type
declare -a test_list=(
   "regr/fi_basic.yml"
)

# Check if a YML file is passed as an argument
if [ $# -gt 0 ]; then
    # If argument passed, treat it as a file to use as the test list
    test_list=("$@")
    echo "Running tests with the provided YML files: ${test_list[@]}"
else
    echo "No YML file provided, using default list: ${test_list[@]}"
fi

echo "Running with config (H, W)=($PE_H, $PE_W), MODE=$MODE"

# Read the list values with space
for val in "${test_list[@]}"; do
    nice -n10 regr/bwruntests.py --report_junit -t ${TIMEOUT} --yaml -o regr/neureka_tests.xml -p${N_PROC} --perf regr/perf.json $val
    if test $? -ne 0; then
        echo "Error in test $val with config (H, W)=($PE_H, $PE_W), MODE=$MODE"
    fi
done

unset P_STALL
unset PE_H
unset PE_W
unset MODE
