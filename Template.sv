// =========================================================================
// Projekt: A1200_NG
// Datei:   Template.sv
// Teil:    1 von 2 (Modul-Schnittstelle und Bereinigtes OSD-Menü)
// Funktion: Der Haupt-Top-Level-Wrapper (emu) für das MiSTer-Framework.
// SANIERUNG MASTER-EDITION (COMMODORE RESET-COMPLIANT):
//   - Bereitet die Takt- und IOCTL-Strukturen für die NE555-Logik vor. [14.1]
// =========================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  
assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;

assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 

// =========================================================================
// OSD-MENÜSTRUKTUR - RADIKAL BEREINIGT (NUR NOCH ORIGINALE HARDWARE) [14.1]
// =========================================================================
localparam CONF_STR = {
	"A1200_NG;;",
	"-;",
	"H10O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O2,TV Mode,NTSC,PAL;",                          
	"-;",
	"F0,ROM,Load Kickstart;",                        
	"F1,ADF,Mount DF0:;",                            
	"-;",
	"S0,HDF,Mount HDF0:;",                           
	"S1,HDF,Mount HDF1:;",                           
	"S2,HDF,Mount HDF2:;",                           
	"S3,HDF,Mount HDF3:;",                           
	"-;",
	"T0,Reset;",                                      
	"R0,Reset and close OSD;",
	"V,v", `BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wr;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(status),                   
	.ps2_key(ps2_key),
	.ioctl_download(ioctl_download),
	.ioctl_index   (ioctl_index),
	.ioctl_addr    (ioctl_addr),
	.ioctl_dout    (ioctl_dout),
	.ioctl_wr      (ioctl_wr)
);

wire clk_sys; 
wire ce_pix;

pll_0002 my_hardware_pll
(
	.refclk(CLK_50M),
	.rst(RESET),
	.outclk_0(clk_sys)
);

wire reset = RESET | status[0] | buttons[1] | ioctl_download; // Triggersignal vom Framework / OSD
wire amiga_reset_extended;                     // Das gedehnte, unnachgiebige Hardwarereset-Signal [14.1]

wire [7:0] core_r, core_g, core_b;
wire HBlank, HSync, VBlank, VSync;

// =========================================================================
// INTERNE IOCTL-STEUERWEICHEN
// =========================================================================
wire ioctl_ks_download   = (ioctl_download && ioctl_index == 8'd0);
wire ioctl_fdd_download  = (ioctl_download && ioctl_index == 8'd1);
wire ioctl_hdf0_download = (ioctl_download && ioctl_index == 8'd2);
wire ioctl_hdf1_download = (ioctl_download && ioctl_index == 8'd3);
wire ioctl_hdf2_download = (ioctl_download && ioctl_index == 8'd4);
wire ioctl_hdf3_download = (ioctl_download && ioctl_index == 8'd5);

// =========================================================================
// NE555 TIMER-EMULATION: ZENTRALE AMIGA 1200 RESET-LOGIK (U14)
// Dehnt den ultrakurzen OSD-Trigger auf Commodore-konforme ~250ms aus! [14.1]
// =========================================================================
NE555 my_hardware_reset_timer
(
	.i_clk_sys       (clk_sys),              // 50 MHz synchrone Zeitbasis
	.i_trigger_reset (reset),                // Der kurze Eingangsimpuls
	.o_amiga_reset   (amiga_reset_extended)  // Die betonierte Hardware-Resetleitung [14.1]
);

A1200_top my_amiga_1200
(
	.clk_sys           (clk_sys),
	.reset             (amiga_reset_extended), // Angeschlossen an das gedehnte Signal! [14.1]
	.pal_mode          (status[2]),                   
	.ce_pix            (ce_pix),
	.HBlank            (HBlank),
	.HSync             (HSync), 
	.VBlank            (VBlank),
	.VSync             (VSync),
	.video_r           (core_r),
	.video_g           (core_g),
	.video_b           (core_b),
	.kbd_clk           (1'b1), .kbd_data (1'b1), .kbd_reset(amiga_reset_extended), 
	.mouse_x (2'b00), .mouse_y (2'b00), .mouse_btn(2'b00),
	.ioctl_addr        (ioctl_addr), .ioctl_data(ioctl_dout), .ioctl_wr(ioctl_wr),
	.ioctl_ks_download (ioctl_ks_download), .ioctl_fdd_download(ioctl_fdd_download),
	.ioctl_hdf0_download(ioctl_hdf0_download), .ioctl_hdf1_download(ioctl_hdf1_download),
	.ioctl_hdf2_download(ioctl_hdf2_download), .ioctl_hdf3_download(ioctl_hdf3_download)
);

// =========================================================================
// FINALE GEHÄUSE-ZUWEISUNGEN DIREKT AN DIE HARDWARE-PINS DES BOARDS
// =========================================================================
assign CLK_VIDEO     = clk_sys; 
assign CE_PIXEL      = ce_pix;    

assign VGA_DE        = ~(HBlank | VBlank);
assign VGA_HS        = HSync;
assign VGA_VS        = VSync;

assign VGA_R         = core_r;
assign VGA_G         = core_g;
assign VGA_B         = core_b;

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 

assign LED_USER      = act_cnt ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
