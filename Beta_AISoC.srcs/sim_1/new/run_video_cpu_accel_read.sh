#!/usr/bin/env bash
set -Eeuo pipefail

SIM_DIR="/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.sim/sim_1/behav/xsim"
SRC_DIR="/home/raven1911/Data/vivado_prj/Beta_AISoC/Beta_AISoC.srcs"

export RDI_DATADIR="/home/raven1911/Vivado/Vivado/2024.2/data"

cd "$SIM_DIR"

xvlog --incr --relax --work xil_defaultlib \
    "$SRC_DIR/sources_1/new/axi4_stream.v" \
    "$SRC_DIR/sources_1/imports/sources_1/imports/new/axi_lite_slave_interface.v" \
    "$SRC_DIR/sources_1/new/cnn_ifbuf_dma_mux.v" \
    "$SRC_DIR/sources_1/new/video_streaming_axi_lite_core.v" \
    > video_cpu_accel_compile.log 2>&1

xvlog --incr --relax --sv --work xil_defaultlib \
    "$SRC_DIR/sim_1/new/Beta_AISoC_Video_CPUCfg_AccelRead_tb.sv" \
    >> video_cpu_accel_compile.log 2>&1

xelab --incr --debug typical --relax --mt 8 \
    -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -L xpm \
    --snapshot Beta_AISoC_Video_CPUCfg_AccelRead_tb_behav \
    xil_defaultlib.Beta_AISoC_Video_CPUCfg_AccelRead_tb xil_defaultlib.glbl \
    -log video_cpu_accel_elaborate.log > /dev/null 2>&1

xsim Beta_AISoC_Video_CPUCfg_AccelRead_tb_behav \
    -key {Behavioral:sim_1:Functional:Beta_AISoC_Video_CPUCfg_AccelRead_tb} \
    -tclbatch "$SRC_DIR/sim_1/new/Beta_AISoC_Video_CPUCfg_AccelRead_tb.tcl" \
    -log video_cpu_accel_simulate.log > /dev/null 2>&1

if grep -Eq 'Fatal:|ERROR DATA|ERROR TLAST|AXI .*timeout|FAIL' video_cpu_accel_simulate.log; then
    exit 1
fi
