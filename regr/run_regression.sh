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

export N_PROC=20
export P_STALL=0.04
TIMEOUT=200

# Declare a string array with type
declare -a test_list=(
    "regr/basic.yml"
)

# Read the list values with space
for val in "${test_list[@]}"; do
    nice -n10 regr/bwruntests.py --report_junit -t ${TIMEOUT} --yaml -o regr/neureka_tests.xml -p${N_PROC} $val
    if test $? -ne 0; then
        echo "Error in test $val"
        exit 1
    fi
done
unset P_STALL
