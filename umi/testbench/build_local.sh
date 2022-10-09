\rm a.out

iverilog tb_umi_fifo.v \
	 -y . \
	 -y ../rtl \
	 -y ../../../lambdalib/stdlib/rtl \
	 -y ../../../lambdalib/ramlib/rtl

./a.out +MEMHFILE=./hello.memh
./a.out +MEMHFILE=./buffer.memh
