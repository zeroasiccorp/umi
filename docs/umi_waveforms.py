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

######################
# Transaction Examples
######################
# Okay: Valid before ready.
svg = wavedrom.render("""
{
  "signal": [
    {                   "node": ".....-..", phase: 0.2 },
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x..2.x..", "data": "Data" },
    { "name": "valid",  "wave": "0..1.0.." },
    { "name": "ready",  "wave": "0...10..", },
    {                   "node": "....._..", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample"
  ],
}
""")
svg.saveas("_images/ok_valid_ready.svg")

# Okay: Ready before valid.
svg = wavedrom.render("""
{
  "signal": [
    {                   "node": "......-.", phase: 0.2 },
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x....2x.", "data": "Data" },
    { "name": "valid",  "wave": "0....10." },
    { "name": "ready",  "wave": "01....0." },
    {                   "node": "......_.", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample"
  ],
}
""")
svg.saveas("_images/ok_ready_valid.svg")

# Okay: Ready and valid in same cycle.
svg = wavedrom.render("""
{
  "signal": [
    {                   "node": "......-.", phase: 0.2 },
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x....2x.", "data": "Data" },
    { "name": "valid",  "wave": "0....10." },
    { "name": "ready",  "wave": "0....10." },
    {                   "node": "......_.", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample"
  ],
}
""")
svg.saveas("_images/ok_sametime.svg")

# Okay: Ready toggles without valid..
svg = wavedrom.render("""
{
  "signal": [
    {                   "node": "......-.", phase: 0.2 },
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x....2x.", "data": "Data" },
    { "name": "valid",  "wave": "0....10." },
    { "name": "ready",  "wave": "010..10." },
    {                   "node": "......_.", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample"
  ],
}
""")
svg.saveas("_images/ok_ready_toggle.svg")

# NOT okay: Valid toggles without ready.
svg = wavedrom.render("""
{
  "signal": [
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x4x..2x.", "data": "XXX Data" },
    { "name": "valid",  "wave": "010..10." },
    { "name": "ready",  "wave": "0....10." },
  ],
}
""")
svg.saveas("_images/bad_valid_toggle.svg")

# Okay: Valid held high for two cycles (two transactions)
svg = wavedrom.render("""
{
  "signal": [
    {                   "node": ".....-=.", phase: 0.2 },
    { "name": "clk",    "wave": "P.......", period = 2 },
    { "name": "packet", "wave": "x...2.x.", "data": "Data" },
    { "name": "valid",  "wave": "0...1.0." },
    { "name": "ready",  "wave": "0.1...0." },
    {                   "node": "....._!.", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample 1", "=|! sample 2",
  ],
}
""")
svg.saveas("_images/ok_double_xaction.svg")

# Example 'read' transaction: TX to request read, RX to receive.
svg = wavedrom.render("""
{
  "signal": [
    {                       "node": "...=..-.", phase: 0.2 },
    { "name": "clk",        "wave": "P.......", period = 2 },
    { "name": "packet_in",  "wave": "x2.x....", "data": "Req" },
    { "name": "valid_in",   "wave": "01.0...." },
    { "name": "ready_in",   "wave": "0.10...." },
    { "name": "packet_out", "wave": "x....2x.", "data": "Resp" },
    { "name": "valid_out",  "wave": "0....10." },
    { "name": "ready_out",  "wave": "0..1..0." },
    {                       "node": "...!.._.", phase: 0.2 },
  ],
  "edge": [
    "-|_ sample out", "=|! sample in"
  ],
}
""")
svg.saveas("_images/example_rw_xaction.svg")

