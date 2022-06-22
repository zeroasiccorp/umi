import wavedrom

######################
# READY VALID
######################
svg = wavedrom.render("""
{ "signal": [
 { "name": "clk",    "wave": "P........", period=2},
 { "name": "valid_out",  "wave": "0.1.01..0"},
 { "name": "packet_out", "wave": "x.23x4.5x", "data": "P0 P1 P2 P3"},
 { "name": "ready_in",  "wave": "1....01.."},

]}""")
svg.saveas("_images/ready_valid.svg")
