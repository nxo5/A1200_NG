`timescale 1ns/10ps
module  pll_0002(

	// interface 'refclk' (Der physikalische 50-MHz-Quarz des DE10-Nano)
	input wire refclk,

	// interface 'reset'
	input wire rst,

	// interface 'outclk0' - Speist die Hauptplatine mit harten 50 MHz!
	output wire outclk_0,

	// interface 'outclk1' - Speist deinen Debugscreen mit 65 MHz! [14.1]
	output wire outclk_1,

	// interface 'locked'
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		
		// Aktiviert beide Hardware-Taktkanäle im FPGA-Silizium [14.1]
		.number_of_clocks(1),
		
		// Kanal 0: Exakt 50.000000 MHz (Die geforderte Basis für Alice!) [14.1]
		.output_clock_frequency0("50.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		
		// Kanal 1: Exakt 65.000000 MHz (Der unzerstörbare VESA XGA-Standard) [14.1]
		.output_clock_frequency1("65.000000 MHz"),
		.phase_shift1("0 ps"),
		.duty_cycle1(50),
		
		.output_clock_frequency2("0 MHz"),
		.phase_shift2("0 ps"),
		.duty_cycle2(50),
		.output_clock_frequency3("0 MHz"),
		.phase_shift3("0 ps"),
		.duty_cycle3(50),
		.output_clock_frequency4("0 MHz"),
		.phase_shift4("0 ps"),
		.duty_cycle4(50),
		.output_clock_frequency5("0 MHz"),
		.phase_shift5("0 ps"),
		.duty_cycle5(50),
		.output_clock_frequency6("0 MHz"),
		.phase_shift6("0 ps"),
		.duty_cycle6(50),
		.output_clock_frequency7("0 MHz"),
		.phase_shift7("0 ps"),
		.duty_cycle7(50),
		.output_clock_frequency8("0 MHz"),
		.phase_shift8("0 ps"),
		.duty_cycle8(50),
		.output_clock_frequency9("0 MHz"),
		.phase_shift9("0 ps"),
		.duty_cycle9(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst	(rst),
		
		// Reicht beide synchronen Taktlinien an deine Template.sv weiter! [14.1]
		.outclk	({outclk_1, outclk_0}),
		
		.locked	(locked),
		.fboutclk	( ),
		.fbclk	(1'b0),
		.refclk	(refclk)
	);
endmodule

