/*
 * Copyright (C) 2018-2024 ETH Zurich and University of Bologna
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
 * Authors:  Francesco Conti <f.conti@unibo.it>
 *           Renzo Andri <andrire@iis.ee.ethz.ch>
 *           Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 */
#include <stdio.h>
#include "tinyprintf.h"

#ifndef __HAL_NEUREKA_H__
#define __HAL_NEUREKA_H__

/* REGISTER MAP */

#define NEUREKA_ADDR_BASE 0x00100000

// commands
#define NEUREKA_TRIGGER        0x00
#define NEUREKA_ACQUIRE        0x04
#define NEUREKA_FINISHED       0x08
#define NEUREKA_STATUS         0x0c
#define NEUREKA_RUNNING_JOB    0x10
#define NEUREKA_SOFT_CLEAR     0x14
#define NEUREKA_SWSYNC         0x18
#define NEUREKA_URISCY_IMEM    0x1c

// job configuration
#define NEUREKA_REGISTER_OFFS       0x20
#define NEUREKA_REG_WEIGHTS_PTR     0x00
#define NEUREKA_REG_INFEAT_PTR      0x04
#define NEUREKA_REG_OUTFEAT_PTR     0x08
#define NEUREKA_REG_SCALE_PTR       0x0c
#define NEUREKA_REG_SCALE_SHIFT_PTR 0x10
#define NEUREKA_REG_SCALE_BIAS_PTR  0x14

/* LOW-LEVEL HAL */
#define CEIL(VARIABLE) ( (VARIABLE - (int)VARIABLE)==0 ? (int)VARIABLE : (int)VARIABLE+1 )
#define DIVNCEIL(X,Y) (X+Y-1)/Y // devide and ceil with integer only, works for positive numbers only!

// TODO For all the following functions we use __builtin_pulp_OffsetedWrite and __builtin_pulp_OffsetedRead
// instead of classic load/store because otherwise the compiler is not able to correctly factorize
// the NEUREKA base in case several accesses are done, ending up with twice more code

#define NEUREKA_WRITE_CMD(offset, value) *(int volatile *)(NEUREKA_ADDR_BASE + offset) = value
#define NEUREKA_WRITE_CMD_BE(offset, value, be) *(char volatile *)(NEUREKA_ADDR_BASE + offset + be) = value
#define NEUREKA_READ_CMD(offset) *(int volatile *)(NEUREKA_ADDR_BASE + offset)

#define NEUREKA_WRITE_REG(offset, value) *(int volatile *)(NEUREKA_ADDR_BASE + NEUREKA_REGISTER_OFFS + offset) = value
#define NEUREKA_WRITE_REG_BE(offset, value, be) *(char volatile *)(NEUREKA_ADDR_BASE + NEUREKA_REGISTER_OFFS + offset + be) = value
#define NEUREKA_READ_REG(offset) *(int volatile *)(NEUREKA_ADDR_BASE + NEUREKA_REGISTER_OFFS + offset)

int ne16_compare(uint8_t *actual_y, uint8_t *golden_y, int len) {
  uint8_t actual_byte = 0;
  uint8_t golden_byte = 0;
  uint8_t actual = 0;
  uint8_t golden = 0;

  int errors = 0;
  int non_zero_values = 0;

  int max_value_saturated = 0x80; // FIXME

  for (int i=0; i<len; i++) {
    actual_byte = *(actual_y+i);
    golden_byte = *(golden_y+i);

    int error = (int) (actual_byte != golden_byte);
    errors += (int) (actual_byte != golden_byte);
    non_zero_values += (int) (actual_byte != 0 && actual_byte != max_value_saturated);
  }
  // raise error "9999" if all values are zero
  //if(non_zero_values==0) { errors = 9999; }
  return errors;
}

int ne16_compare_int(uint32_t *actual_y, uint32_t *golden_y, int len) {
  uint32_t actual_word = 0;
  uint32_t golden_word = 0;
  uint32_t actual = 0;
  uint32_t golden = 0;

  int errors = 0;
  int non_zero_values = 0;

  int max_value_saturated = 0x80; // FIXME

  for (int i=0; i<len; i++) {
    actual_word = *(actual_y+i);
    golden_word = *(golden_y+i);

    int error = (int) (actual_word != golden_word);
    errors += (int) (actual_word != golden_word);
#ifndef NVERBOSE
    if(error) {
      if(errors==1) tfp_printf("  golden     <- actual     @ address    @ index\n");
      tfp_printf("  0x%08x <- 0x%08x @ 0x%08x @ 0x%08x\n", golden_word, actual_word, (actual_y+i), i*4);
    }
#endif /* NVERBOSE */
    non_zero_values += (int) (actual_word != 0 && actual_word != max_value_saturated);
  }
  // raise error "9999" if all values are zero
  //if(non_zero_values==0) { errors = 9999; }
  return errors;
}

#endif /* __HAL_NEUREKA_H__ */
