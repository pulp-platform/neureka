#!/usr/bin/env python
#
# uloop_compile.sv
# Francesco Conti <fconti@iis.ee.ethz.ch>
#
# Copyright (C) 2017-2019 ETH Zurich, University of Bologna
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# See LICENSE.sw.txt for details.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from __future__ import print_function
from uloop_common import *

loops_ops,code,mnem = uloop_load("code.yml")

bytecode = uloop_bytecode(code, loops_ops)
print (bytecode['code'].length)
print ("uloop bytecode: %d'h%s" % (bytecode['code'].length, str(bytecode['code'].hex)))
print ("uloop loops:    %d'b%s" % (bytecode['loops'].length, str(bytecode['loops'].bin)))
