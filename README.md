# NEureka - The Neural Network Accelerator of ArchiMEDES
NEureka is a Deep Neural Network accelerator which exploits the Hardware Processing Engine (HWPE) paradigm [1]  (https://hwpe-doc.rtfd.io) and is designed to be integrated in an open-source PULP cluster configuration in combination with the Heterogeneous Cluster Interconnect (HCI). It makes use of the open-source IPs 'hci', 'hwpe-ctrl', and 'hwpe-stream'.
 
In general NEureka has built-in HW supports the following features:
 
- Filters: 1x1, 3x3, depthwise
- Batch normalization
- ReLU
- Activation input bits: 8
- Weight bits: 2,3,4,5,6,7,8
- Activation output bits: 8,32
- Nr of input channels: arbitrary
- Nr of output channels: arbitrary
 
NEureka is a direct derivative of the NE16 design https://github.com/pulp-platform/ne16 .

## Simulating

### Building the hardware simulation environment
The simulation infrastructure of NEureka uses QuestaSim.
To build the environment, you can run the following with QuestaSim in your `PATH`:
```
# fetch Bender (if not available), update the dependencies, and generate the scripts
make update-ips
# build the simulation environment
make hw-all
```

### Setting up the software environment
This version of NEureka relies on the https://github.com/pulp-platform/pulp-nnx library to generate simulation stimuli. You can fetch it in the `model/deps` folder as a submodule:
```
git submodule update --init
```
The `pulp-nnx` library has several Python requirements, such as PyTorch. Refer to `model/requirements.txt` for a list; you can install a Python VirtualEnv by running the `create_venv.sh` script and then entering the created environment:
```
source create_venv.sh
source venv/bin/activate
```
You also need a RISC-V GCC toolchain, i.e., `riscv32-unknown-elf-gcc` must be in your `PATH`.

### Generating stimuli and running the simulation
You can generate stimuli with
```
make stimuli 
```
To build the software generated test,
```
make sw-all
```
Finally, to run it:
```
# without QuestaSim GUI
make run
# with GUI
make run gui=1
```
There are several controllable parameters, such as filter size `FS` (1 or 3), input spatial size `H_IN` and `W_IN`, input channels `K_IN`, output channels `K_OUT`, depthwise conv (with `FS=3`) `DW`.
See the `Makefile` for a full list. All simulation commands should be augmented with modified parameters, e.g.,
```
make stimuli H_IN=7 W_IN=3 K_OUT=32 K_IN=32
make sw-all run H_IN=7 W_IN=3 K_OUT=32 K_IN=32 gui=0
```

## Contributors
- Arpan Suravi Prasad, ETH Zurich (*prasadar@iis.ee.ethz.ch*)
- Francesco Conti, University of Bologna (*f.conti@unibo.it*)
 
# License
This repository makes use of two licenses:
- for all *software*: Apache License Version 2.0
- for all *hardware*: Solderpad Hardware License Version 0.51
 
For further information have a look at the license files: `LICENSE.hw`, `LICENSE.sw`

# References
- A. S. Prasad, L. Benini and F. Conti, "Specialization meets Flexibility: a Heterogeneous Architecture for High-Efficiency, High-flexibility AR/VR Processing," 2023 60th ACM/IEEE Design Automation Conference (DAC), San Francisco, CA, USA, 2023, pp. 1-6, doi: 10.1109/DAC56929.2023.10247945.
- A. S. Prasad, M. Scherer, F. Conti, D. Rossi, A. Di Mauro, M. Eggimann, J. T. Gómez, Z. Li, S. Shakib Sarwar, Z. Wang, B. De Salvo, and L. Benini, "Siracusa: A 16 nm Heterogenous RISC-V SoC for Extended Reality with At-MRAM Neural Engine," IEEE Journal of Solid-State Circuits, 2024 (accepted), arXiv: https://arxiv.org/abs/2312.14750.