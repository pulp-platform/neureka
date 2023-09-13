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
 
## Contributors
- Arpan Suravi Prasad, ETH Zurich (*prasadar@iis.ee.ethz.ch*)
- Francesco Conti, University of Bologna (*f.conti@unibo.it*)
 
# License
This repository makes use of two licenses:
- for all *software*: Apache License Version 2.0
- for all *hardware*: Solderpad Hardware License Version 0.51
 
For further information have a look at the license files: `LICENSE.hw`, `LICENSE.sw`

# References
[1] F. Conti, P. Schiavone, and L Benini. "XNOR neural engine: A hardware accelerator IP for 21.6-fJ/op binary neural network inference." IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems 37.11 (2018): 2940-2951.
