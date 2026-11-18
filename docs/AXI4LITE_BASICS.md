# AXI4-Lite basics


## The one-line idea
AXI4-Lite is a simple bus that lets one chip block (the **master**, for example a CPU) read and write small control registers inside another block (the **slave**). Think of the slave as a cupboard with numbered lockers. The master says "put this number in locker 3" (write) or "what is in locker 3?" (read).

In our project the slave has **16 lockers (registers), each 32 bits wide**.

## The five channels
A bus has wires. AXI groups them into 5 independent channels, each carrying one kind of message:

| Channel | Direction | Carries | Our signals |
|---|---|---|---|
| **AW** (write address) | master to slave | where to write | `awvalid`, `awready`, `awaddr` |
| **W** (write data) | master to slave | what to write and which bytes | `wvalid`, `wready`, `wdata`, `wstrb` |
| **B** (write response) | slave to master | "write done" or error | `bvalid`, `bready`, `bresp` |
| **AR** (read address) | master to slave | where to read | `arvalid`, `arready`, `araddr` |
| **R** (read data) | slave to master | the data and read status | `rvalid`, `rready`, `rdata`, `rresp` |

A write uses AW + W + B. A read uses AR + R. The channels are independent, so the address and the data of a write may arrive at different times.

## The VALID/READY handshake (the most important rule)
Every channel has two wires:
- **VALID**: the sender says "I have something for you".
- **READY**: the receiver says "I can take it now".

A transfer happens on a clock edge where **both are 1**. Key rule from the AXI spec: **once VALID is 1, it must stay 1, and the data must not change, until READY becomes 1.** The sender cannot take it back. This is the rule most of our assertions check.

## Other terms you will hear
- **Clock `aclk`**: everything happens on the rising edge. Ours is 100 MHz (10 ns period).
- **Reset `aresetn`**: active low. When it is 0, everything goes back to the start state (all registers 0, no response pending).
- **WSTRB (write strobe)**: 4 bits, one per byte of the 32-bit word. `4'hF` writes all four bytes. `4'h1` writes only the lowest byte. `4'h0` writes nothing.
- **Response codes (2 bits)**:
  - `00` OKAY: it worked.
  - `10` SLVERR: slave error (for us: address out of range).
  - `01` EXOKAY: **not allowed in AXI4-Lite**.
  - `11` DECERR: decode error. **Our slave never gives it.**
- **Address map**: register number = address bits [5:2]. Addresses 0x00 to 0x3C are the 16 registers. Anything 0x40 or above is out of range. Bits [1:0] are ignored (a word is 4 bytes).
- **Backpressure**: the receiver keeps READY low for a while, so the sender must wait.
- **DUT**: "design under test", our slave.
- **Testbench (TB)**: the program that tests the DUT. It is not hardware. It never goes into a chip.

