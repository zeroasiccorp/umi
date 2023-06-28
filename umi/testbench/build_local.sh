\rm -f a.out

iverilog tb_umi_arbiter.v \
	 -y . \
	 -y ../rtl \
	 -I . \
	 -I ../rtl \
	 -y ../../submodules/lambdalib/stdlib/rtl \
	 -y ../../submodules/lambdalib/ramlib/rtl

./a.out
#./a.out +MEMHFILE=./hello.memh
#./a.out +MEMHFILE=./buffer.memh
