#!/usr/bin/env bash
set -Eeuo pipefail

SIM_DIR="/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.sim/sim_1/behav/xsim"
SRC_DIR="/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.srcs/sim_1/new"
SNAPSHOT="Beta_AISoC_CNN_DMA_Path_cam_ifmap_behav"

export RDI_DATADIR="/home/raven1911/Vivado/Vivado/2024.2/data"

cd "$SIM_DIR"

xvlog --incr --relax -prj Beta_AISoC_CNN_DMA_Path_tb_vlog.prj \
    > cam_ifmap_bmem_compile.log 2>&1

xelab --incr --debug typical --relax --mt 8 \
    -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -L xpm \
    -generic_top RUN_CAMERA_IFMAP_TEST=1 \
    -generic_top UART_AXI_PRINT=0 \
    -generic_top QUIET_TB_LOG=0 \
    --snapshot "$SNAPSHOT" \
    xil_defaultlib.Beta_AISoC_CNN_DMA_Path_tb xil_defaultlib.glbl \
    -log cam_ifmap_bmem_elaborate.log > /dev/null 2>&1

xsim "$SNAPSHOT" \
    -key {Behavioral:sim_1:Functional:Beta_AISoC_CNN_DMA_Path_cam_ifmap} \
    -tclbatch "$SIM_DIR/Beta_AISoC_CNN_DMA_Path_tb.tcl" \
    -log cam_ifmap_bmem_simulate.log > /dev/null 2>&1

if grep -Eq 'Fatal:|ERROR:|FAIL|TIMEOUT|Trap detected' cam_ifmap_bmem_simulate.log; then
    exit 1
fi
