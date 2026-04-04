
Adarsh Rajesh - ar77947
only diff to spec is that alu/fpu split up into two diff modules for more modularity

run test benches with 

iverilog -g2012 -I . -o test.out testbenchfilename.sv
vvp test.out\

iverilog -g2012 -I . -o cpu.out tinker.sv
vvp cpu.out\