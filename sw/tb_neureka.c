/*
 * Copyright (C) 2020-2024 ETH Zurich and University of Bologna
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
 */

/*
 * Authors:  Francesco Conti <fconti@iis.ee.ethz.ch>
 *           Gianna Paulin <pauling@iis.ee.ethz.ch>
 *           Renzo Andri <andrire@iis.ee.ethz.ch>
 *           Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 * Main Test Program for the RBE
 */

#include <stdint.h>
#include <stdio.h>

#include "hal_ne16.h"

#include "inc/neureka_cfg.h"
#include "inc/neureka_infeat.h"
#include "inc/neureka_weights.h"
#include "inc/neureka_scale.h"
#include "inc/neureka_scale_bias.h"
#include "inc/neureka_scale_shift.h"
#include "inc/neureka_streamin.h"
#include "inc/neureka_outfeat.h"

int main() {

  uint8_t volatile *x = neureka_infeat;
  uint8_t volatile *W = neureka_weights;
  uint8_t volatile *nq = neureka_scale; //stim_nq;
  uint8_t volatile *nqs = neureka_scale_shift;
  uint8_t volatile *nqb = neureka_scale_bias;
  uint8_t volatile *y = neureka_outfeat;

  uint8_t volatile *golden_y = y;
  uint8_t volatile *actual_y = neureka_streamin;
  tfp_printf("--------------DEBUG PTR----------------------\n");
  printf("Weight PTR: %x\n",(unsigned int)W);
  printf("Input Feature PTR: %x\n",(unsigned int)x);
  printf("Output Feature PTR: %x\n",(unsigned int)actual_y);
  printf("Scale PTR: %x\n",(unsigned int)nq);
  printf("Scale shift PTR: %x\n",(unsigned int)nqs);
  printf("Scale bias PTR: %x\n",(unsigned int)nqb);

  // soft-clear NE16
  NEUREKA_WRITE_CMD(NEUREKA_SOFT_CLEAR, 0);
  for(volatile int kk=0; kk<10; kk++);

  // acquire a NE16 job
  do {} while(NEUREKA_READ_CMD(NEUREKA_ACQUIRE) < 0);

  // program NE16
  NEUREKA_WRITE_REG(NEUREKA_REG_WEIGHTS_PTR,     W);
  NEUREKA_WRITE_REG(NEUREKA_REG_INFEAT_PTR,      x);
  NEUREKA_WRITE_REG(NEUREKA_REG_OUTFEAT_PTR,     actual_y);
  NEUREKA_WRITE_REG(NEUREKA_REG_SCALE_PTR,       nq);
  NEUREKA_WRITE_REG(NEUREKA_REG_SCALE_SHIFT_PTR, nqs);
  NEUREKA_WRITE_REG(NEUREKA_REG_SCALE_BIAS_PTR,  nqb);
  for(int i=6; i<24; i++) {
    NEUREKA_WRITE_REG(i*4, neureka_cfg[i]);
  }

  // trigger NE16 computation
  NEUREKA_WRITE_CMD(0, NEUREKA_TRIGGER);

  // wait for end of computation
  asm volatile ("wfi" ::: "memory");
  do {} while(NEUREKA_READ_CMD(NEUREKA_STATUS) != 0);

  int errors = neureka_compare_int(actual_y, golden_y, STIM_Y_SIZE/4);
  
  tfp_printf("[STDOUT] Total errors: %d/%d\n", errors, STIM_Y_SIZE/4);
  *(int *) (0x80000000) = errors; 
  *(int *) (0x80000004) = 1;
  return 0;
}
