\rm -f a.out

MAIN_DIR=$(pwd)/../..
RTL_DIR=$MAIN_DIR/utils/rtl

iverilog \
    -y . \
    -I . \
    -y $RTL_DIR \
    -I $RTL_DIR \
    -y $MAIN_DIR/umi/rtl \
    -I $MAIN_DIR/umi/rtl \
    -y $MAIN_DIR/../lambdalib/lambdalib/padring/rtl \
    -I $MAIN_DIR/../lambdalib/lambdalib/padring/rtl \
    -y $MAIN_DIR/../lambdalib/lambdalib/stdlib/rtl \
    -y $MAIN_DIR/../lambdalib/lambdalib/vectorlib/rtl \
    -y $MAIN_DIR/../lambdalib/lambdalib/ramlib/rtl \
    tb_axilite2umi.v

#./a.out
./a.out +MEMHFILE=./buffer_axilite.memh
#./a.out +MEMHFILE=$MAIN_DIR/umi/testbench/buffer.memh
