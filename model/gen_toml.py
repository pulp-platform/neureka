import argparse
import toml

# Define the argument parser
parser = argparse.ArgumentParser(description='Generate a conf.toml file based on input arguments.')

# Add arguments
parser.add_argument('--in_height', type=int, required=True)
parser.add_argument('--in_width', type=int, required=True)
parser.add_argument('--in_channel', type=int, required=True)
parser.add_argument('--out_channel', type=int, required=True)
parser.add_argument('--depthwise', action='store_true')
parser.add_argument('--kernel_height', type=int, required=True)
parser.add_argument('--kernel_width', type=int, required=True)
parser.add_argument('--stride_height', type=int, required=True)
parser.add_argument('--stride_width', type=int, required=True)
parser.add_argument('--padding_top', type=int, required=False, default=0)
parser.add_argument('--padding_bottom', type=int, required=False, default=0)
parser.add_argument('--padding_left', type=int, required=False, default=0)
parser.add_argument('--padding_right', type=int, required=False, default=0)
parser.add_argument('--in_type', type=str, required=False, default="uint8")
parser.add_argument('--out_type', type=str, required=False, default="uint8")
parser.add_argument('--weight_type', type=str, required=False, default="int8")
parser.add_argument('--scale_type', type=str, required=False, default="uint8")
parser.add_argument('--bias_type', type=str, required=False, default="int32")
parser.add_argument('--no_norm_quant', action='store_true')
parser.add_argument('--no_bias', action='store_true')
parser.add_argument('--no_relu', action='store_true')

# Parse the arguments
args = parser.parse_args()

# Organize the configuration data
config_data = {
    'in_height': args.in_height,
    'in_width': args.in_width,
    'in_channel': args.in_channel,
    'out_channel': args.out_channel,
    'depthwise': args.depthwise,
    'kernel_shape': {
        'height': args.kernel_height,
        'width': args.kernel_width,
    },
    'stride': {
        'height': args.stride_height,
        'width': args.stride_width,
    },
    'padding': {
        'top': args.padding_top,
        'bottom': args.padding_bottom,
        'left': args.padding_left,
        'right': args.padding_right,
    },
    'in_type': args.in_type,
    'out_type': args.out_type,
    'weight_type': args.weight_type,
    'scale_type': args.scale_type,
    'bias_type': args.bias_type,
    'has_norm_quant': not args.no_norm_quant,
    'has_bias': not args.no_bias,
    'has_relu': not args.no_relu,
}

# Write configuration to a TOML file
with open('conf.toml', 'w') as toml_file:
    toml.dump(config_data, toml_file)
