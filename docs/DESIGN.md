# Design: `rtl/axi_slave_v2.sv`


### What it does in plain words
1. It holds 16 registers.
2. It accepts a write address and write data **independently, in any order**, and remembers them.
3. When it has **both**, it writes the register (only the bytes WSTRB selects) and then raises BVALID with a response.
4. It accepts a read address, then raises RVALID with the register value.
5. Address 0x40 or above: no register changes and the response is SLVERR.
6. Its READY signals depend only on its own state, never on the master's VALID signals.
7. It handles **one write and one read at a time**.

### Line-by-line walk-through

| Lines | What it is | Explanation |
|---|---|---|
| 20-25 | Module and parameters | `ADDR_WIDTH` 32, `DATA_WIDTH` 32, `STRB_WIDTH` = 4, `NUM_REGS` 16 |
| 26-54 | Ports | Port names follow the `s_` prefix convention (`s_awvalid` ... `s_rresp`) |
| 57 | `IDX_W = $clog2(NUM_REGS)` | = 4 bits to pick one of 16 registers |
| 59 | `regs [NUM_REGS]` | The 16 x 32-bit register file (this is 512 flip-flops after synthesis) |
| 62 | `aw_pend, w_pend, ar_pend` | Flags: "an address/data arrived and is waiting". This is how AW and W can come in any order |
| 63-65 | `awaddr_q, araddr_q, wdata_q, wstrb_q` | Stored copies of the accepted address, data and strobe |
| 68 | `s_awready = !aw_pend && !s_bvalid` | Ready to take an address unless one is already waiting or a response is pending. **Only state, no input** |
| 69 | `s_wready = !w_pend && !s_bvalid` | Same for data |
| 70 | `s_arready = !ar_pend && !s_rvalid` | Same for read address |
| 73-76 | Address decode | `w_in_range` is true if address bits [31:6] are all 0, meaning address < 0x40. `w_idx` = bits [5:2] = register number. Same for read |
| 78 | `always_ff @(posedge aclk or negedge aresetn)` | Clocked logic with asynchronous active-low reset |
| 79-92 | Reset branch | Clears all flags, responses and all 16 registers |
| 96-99 | Capture write address | When AWVALID and AWREADY are both 1: set `aw_pend`, store the address |
| 100-104 | Capture write data | When WVALID and WREADY are both 1: set `w_pend`, store data and strobe |
| 106-116 | **Execute the write** | When `aw_pend && w_pend && !s_bvalid`: clear both flags, raise `s_bvalid`. If in range: `s_bresp = 00` and write the bytes (line 112-113: loop over 4 bytes, write byte `j` only if `wstrb_q[j]`). If out of range: `s_bresp = 10`, **no write** |
| 117-119 | Finish the write response | When BVALID and BREADY: drop `s_bvalid` |
| 122-125 | Capture read address | When ARVALID and ARREADY: set `ar_pend`, store address |
| 127-136 | **Execute the read** | When `ar_pend && !s_rvalid`: raise `s_rvalid`. In range: `s_rdata = regs[r_idx]`, `s_rresp = 00`. Out of range: `s_rdata = 0`, `s_rresp = 10` |
| 137-139 | Finish the read | When RVALID and RREADY: drop `s_rvalid` |

### What happens in time (how to read it on a waveform)
**Write:**
1. Master puts AWVALID and WVALID up (any order). READY is normally already high because the slave is idle.
2. On the clock edge where both VALID and READY are 1, the slave stores address or data and sets `aw_pend` or `w_pend`.
3. One edge after **both** pend flags are set, the slave writes the register and raises BVALID.
4. While BVALID is up, AWREADY and WREADY go low (line 68-69). So a second write cannot be swallowed.
5. When BREADY is 1, the handshake happens and BVALID drops.

**Read:**
1. Master puts ARVALID up. ARREADY is normally high.
2. On the handshake edge, the slave stores the address and sets `ar_pend`.
3. One edge later it raises RVALID with the data. ARREADY is low while RVALID is up.
4. When RREADY is 1, the handshake happens and RVALID drops.

### Why it has no state machine
The design uses flags (`aw_pend`, `w_pend`, `ar_pend`, `s_bvalid`, `s_rvalid`) instead of an FSM. That is why IMC reports FSM coverage as "n/a".

