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

#include "nnx_layer.h"
#include <pmsis.h>

#include "neureka.h"
#include "neureka_gvsoc.h"
#include "neureka_testbench_bsp.h"
#include "neureka_task.h"
#include "pulp_nnx_neureka.h"

#define NULL 0

typedef neureka_norm_mode_e nnx_norm_mode_e;
typedef neureka_quant_t nnx_quant_t;
typedef neureka_quant_function_e nnx_quant_function_e;
typedef neureka_norm_t nnx_norm_t;
typedef neureka_task_t nnx_task_t;
typedef neureka_dev_t nnx_dev_t;
typedef neureka_testbench_conf_t nnx_bsp_conf_t;
typedef neureka_task_flag_e nnx_task_flag_e;

#define nnxTaskFlagTrue neurekaTaskFlagTrue
#define nnxTaskFlagFalse neurekaTaskFlagFalse

#define nnx_task_init neureka_task_init
#define nnx_task_set_op_to_conv neureka_task_set_op_to_conv
#define nnx_task_set_bits neureka_task_set_bits
#define nnx_task_set_norm_quant neureka_task_set_norm_quant
#define nnx_task_set_weight_offset neureka_task_set_weight_offset
#define nnx_task_set_weight_source neureka_task_set_weight_source
#define nnx_task_set_activation_prefetch neureka_task_set_activation_prefetch
#define nnx_task_set_dims neureka_task_set_dims
#define nnx_task_set_ptrs_conv neureka_task_set_ptrs_conv
#define nnx_task_set_ptrs_norm_quant neureka_task_set_ptrs_norm_quant

#define nnx_bsp_get_dev neureka_testbench_get_dev

#define nnx_init neureka_nnx_init
#define nnx_dispatch_wait neureka_nnx_dispatch_wait
#define nnx_dispatch neureka_nnx_dispatch
#define nnx_resolve_wait neureka_nnx_resolve_wait
#define nnx_term neureka_nnx_term

// Generated headers
#include "bias.h"
#include "input.h"
#include "layer_conf.h"
#include "output.h"
#include "scale.h"
#include "weight.h"

static void task_prepare(nnx_task_t *task) {
  nnx_task_init(task);
  nnx_task_set_op_to_conv(task, WEIGHT_HEIGHT, GROUPS > 1);
  nnx_task_set_bits(task, INPUT_BITS, OUTPUT_BITS, WEIGHT_BITS);

  nnx_task_set_weight_offset(task, weightOffsetModeLayerWise, WEIGHT_OFFSET);

#ifdef NEUREKA_WEIGHT_SOURCE_WMEM
  nnx_task_set_weight_source(task, neurekaWeightSourceWmem);
  nnx_task_set_activation_prefetch(task, activationPrefetchOn);
#else
  neureka_task_set_weight_source(task, neurekaWeightSourceTcdm);
  nnx_task_set_activation_prefetch(task, activationPrefetchOff);
#endif
#if INPUT_SIGNED == 1
  neureka_task_set_input_signed(task);
#else
  neureka_task_set_input_unsigned(task);
#endif

  const uint32_t w_in_stride = INPUT_CHANNEL * INPUT_BITS / 8;
  const uint32_t h_in_stride = INPUT_WIDTH * w_in_stride;
  const uint32_t w_out_stride = OUTPUT_CHANNEL * OUTPUT_BITS / 8;
  const uint32_t h_out_stride = OUTPUT_WIDTH * w_out_stride;

#if STRIDE_HEIGHT == 2 && STRIDE_WIDTH == 2
  nnx_task_set_dims_stride2x2(
      task, INPUT_HEIGHT, INPUT_WIDTH, INPUT_CHANNEL, h_in_stride, w_in_stride,
      OUTPUT_HEIGHT, OUTPUT_WIDTH, OUTPUT_CHANNEL, h_out_stride, w_out_stride,
      WEIGHT_HEIGHT, WEIGHT_WIDTH, PADDING_TOP, PADDING_BOTTOM, PADDING_LEFT,
      PADDING_RIGHT);
#else
  nnx_task_set_dims(task, INPUT_WIDTH, INPUT_CHANNEL, h_in_stride, w_in_stride,
                    OUTPUT_HEIGHT, OUTPUT_WIDTH, OUTPUT_CHANNEL, h_out_stride,
                    w_out_stride, PADDING_TOP, PADDING_BOTTOM, PADDING_LEFT,
                    PADDING_RIGHT);
#endif

  nnx_task_set_ptrs_conv(task, (uint32_t)input, INPUT_WIDTH, w_in_stride,
                         PADDING_TOP, PADDING_LEFT, (uint32_t)output,
                         (uint32_t)weight);
#if HAS_NORM_QUANT == 1
#if SCALE_BITS == 8
  const nnx_norm_mode_e normMode = normMode8Bit;
#elif SCALE_BITS == 32
  const nnx_norm_mode_e normMode = normMode32Bit;
#endif

  const nnx_task_flag_e flag_bias =
      HAS_BIAS ? nnxTaskFlagTrue : nnxTaskFlagFalse;
  const uint32_t bias_ptr = (uint32_t)(HAS_BIAS ? bias : NULL);

  nnx_quant_function_e quant_function =
      HAS_RELU ? quantFunctionRelu : quantFunctionIdentity;

  nnx_task_set_norm_quant(task,
                          (nnx_quant_t){.shift_amount = OUTSHIFT,
                                        .function = quant_function,
                                        .flag_rounding = nnxTaskFlagFalse},
                          (nnx_norm_t){.mode = normMode,
                                       .flag_bias = flag_bias,
                                       .flag_shift = nnxTaskFlagFalse});

  nnx_task_set_ptrs_norm_quant(task, (uint32_t)scale, NULL, bias_ptr);
#endif // HAS_NORM_QUANT
}

static void task_execute(nnx_task_t *task) {
  nnx_dev_t *dev = nnx_bsp_get_dev();

  nnx_bsp_conf_t conf = {.max_stall = 8};
  nnx_init(dev, &conf);

  nnx_dispatch_wait(dev);

  // printf("CFG:\n");
  // for (int i=0; i<sizeof(neureka_task_data_t)/4; i++) {
  //   printf("%08x\n", ((uint32_t *) &task->data)[i]);
  // }
#if STRIDE_HEIGHT == 2 && STRIDE_WIDTH == 2
  nnx_dispatch_stride2x2(dev, task, INPUT_WIDTH, INPUT_CHANNEL, OUTPUT_HEIGHT,
                         OUTPUT_WIDTH, OUTPUT_CHANNEL, WEIGHT_HEIGHT,
                         WEIGHT_WIDTH);
#else
  nnx_dispatch(dev, task);
#endif

  nnx_resolve_wait(dev, task);

  nnx_term(dev);

}

void execute_nnx_layer(void *args) {
  nnx_task_t task;
  task_prepare(&task);
  task_execute(&task);
}
