#!/hint/bash

# 当 NVIDIA 出现问题时的强力解！

export DRI_PRIME=1
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
export NV_PRIME_RENDER_OFFLOAD=1
export VK_LAYER_NV_optimus=NVIDIA_only
export GLX_VENDOR_LIBRARY_NAME=nvidia
