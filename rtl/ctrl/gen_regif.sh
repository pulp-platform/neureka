#!/bin/bash
peakrdl regblock  neureka_regif.rdl -o regif/ --cpuif obi-flat --default-reset arst_n --hwif-report
peakrdl html      neureka_regif.rdl -o regif/html/
peakrdl c-header  neureka_regif.rdl -o regif/hwpe_ctrl_target.h
