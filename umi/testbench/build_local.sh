\rm -f a.out

iverilog tb_umi_regif.v \
	 -y . \
	 -y ../rtl \
	 -I . \
	 -I ../rtl \
	 -y ../../submoduels/lambdalib/stdlib/rtl \
	 -y ../../submodules/lambdalib/ramlib/rtl

./a.out
//./a.out +MEMHFILE=./hello.memh
//./a.out +MEMHFILE=./buffer.memh
