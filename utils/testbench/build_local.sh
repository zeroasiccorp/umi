\rm -f a.out

MAIN_DIR=$(pwd)/../..
RTL_DIR=$MAIN_DIR/utils/rtl

iverilog tb_umi_data_aggregator.v \
    -y . \
    -I . \
    -y $RTL_DIR \
    -I $RTL_DIR \
    -y $MAIN_DIR/umi/rtl \
    -I $MAIN_DIR/umi/rtl \
    -y $MAIN_DIR/submodules/lambdalib/padring/rtl \
    -I $MAIN_DIR/submodules/lambdalib/padring/rtl \
    -y $MAIN_DIR/submodules/lambdalib/stdlib/rtl \
    -y $MAIN_DIR/submodules/lambdalib/vectorlib/rtl \
    -y $MAIN_DIR/submodules/lambdalib/ramlib/rtl

#./a.out
#./a.out +MEMHFILE=./buffer.memh
./a.out +MEMHFILE=$MAIN_DIR/umi/testbench/buffer.memh
