#!/bin/bash
peakrdl regblock  neureka_regif.rdl -o regif/ --cpuif obi-flat --default-reset arst_n --hwif-report --addr-width 32
peakrdl html      neureka_regif.rdl -o regif/html/
peakrdl c-header  neureka_regif.rdl -o regif/hwpe_ctrl_target.h
# PeakRDL uses unpacked structs to avoid issues at compile time, which is commendable, but incompatible with FIFOing the output of the job!
sed -i 's/typedef[[:space:]]\+struct\b/typedef struct packed/g' regif/neureka_regif_pkg.sv
