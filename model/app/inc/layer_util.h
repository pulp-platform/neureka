/*
 * Luka Macan <luka.macan@unibo.it>
 *
 * Copyright 2023 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef __LAYER_UTIL_H__
#define __LAYER_UTIL_H__

#include "layer_conf.h"
#include <pmsis.h>

static void layer_info() {
  printf("Layer info:\n"
         " - input: (%dx%dx%d)\n"
         " - output: (%dx%dx%d)\n"
         " - weight: (%dx%dx%dx%d)\n"
         " - stride: (%dx%d)\n"
         " - padding: (%dx%dx%dx%d)\n",
         INPUT_HEIGHT, INPUT_WIDTH, INPUT_CHANNEL, OUTPUT_HEIGHT, OUTPUT_WIDTH,
         OUTPUT_CHANNEL, WEIGHT_CHANNEL_OUT, WEIGHT_HEIGHT, WEIGHT_WIDTH,
         WEIGHT_CHANNEL_IN, STRIDE_HEIGHT, STRIDE_WIDTH, PADDING_TOP,
         PADDING_BOTTOM, PADDING_LEFT, PADDING_RIGHT);
}

#endif // __LAYER_UTIL_H__
