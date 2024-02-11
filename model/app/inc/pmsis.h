// fake pmsis.h
#include <stdint.h>
#define PI_L1 __attribute__((section(".data_l1")))
#define PI_L2 __attribute__((section(".data_l1")))
#include "tinyprintf.h"