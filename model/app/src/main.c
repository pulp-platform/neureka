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
 *           Luka Macan <luka.macan@unibo.it>
 * Main Test Program for N-EUREKA
 */

#include <stdint.h>
#include <stdio.h>

#include "layer_util.h"
#include "nnx_layer.h"
#include "output.h"
#include "ecc_check.h"

uint32_t ecc_errs[ECC_REGS];

int main() {

  // execute NNX layer
  execute_nnx_layer(NULL);

  // output checking
  int err = check_output();

  for (int i=0; i < ECC_REGS; i++){
    printf("Internal error detected: %d \n", ecc_errs[i]);
  }

  *(volatile int *) (0x80000000) = ((err != 0) && (ecc_errs[1]==0) && (ecc_errs[3]==0));
  *(volatile int *) (0x80000004) = 1;
  return 0;
}
