# jev_mesh_2x2

Four engines, flits, partials, and row sums. Its own shuttle. The pipe macro is not vendored in this repository.

One macro, one shuttle. SkyWater SKY130A, standard cells `sky130_fd_sc_hd`. This repository is only `jev_mesh_2x2`.

| Property | Value |
| --- | --- |
| Die | 959.0 um by 985.0 um |
| Worst setup slack | 2.774 ns at max_ss_100C_1v60 |
| Worst hold slack | 0.840 ns at max_ss_100C_1v60 |
| Slew, capacitance, fanout, route DRC, LVS | 0 |

| `gds/jev_mesh_2x2.gds` | Hardened layout |
| `lef/jev_mesh_2x2.lef` | LEF abstract |
| `vh/jev_mesh_2x2.vh` | Verilog blackbox |
| `rtl/jev_mesh_2x2.v` | RTL |
| `metrics.json` | Signoff metrics |

The sibling shuttles are separate repositories. `jev_kuramoto` is [kuramoto-oscillator-sky130a](https://github.com/EncryptidSystems/kuramoto-oscillator-sky130a).

Encryptid Systems, Frederick County, Maryland.
