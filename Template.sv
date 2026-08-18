// =========================================================================
// Projekt: A1200_NG
// Datei:   Template.sv
// Funktion: Der Haupt-Top-Level-Wrapper (emu) für das MiSTer-Framework.
// KORREKTUREN:
//   - FIX BIT-SELEKTION: Bindet status[0], status[1] und status[2] isoliert ein!
//   - Tilgt den permanenten Reset-Zustand im Ur-Framework vollkommen.
//   - Vernichtet den fatalen Gatter-Überlauf-Fehler 276003 an der Systempforte.
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
assign HDMI_BLACKOUT = 0;
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
// MINIMIG-KONFORME OSD-MENÜSTRUKTUR
// =========================================================================
localparam CONF_STR = {
	"A1200_NG;;",
	"-;",
	"H10O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O2,TV Mode,NTSC,PAL;",                          // Index 2 im Status-Vektor!
	"-;",
	"F0,Mount DF0:,ADF;",                             // Index 1       
	"-;",
	"S0,Mount HDF0:,HDF;",                            // Index 2        
	"S1,Mount HDF1:,HDF;",                            // Index 3        
	"S2,Mount HDF2:,HDF;",                            // Index 4        
	"S3,Mount HDF3:,HDF;",                            // Index 5        
	"-;",
	"T0,Reset;",                                      // Index 0 im Status-Vektor!
	"R0,Reset and close OSD;",
	"v,0;",                                           // Index 0 (Kickstart-ROM)
	"V,v", `BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

// Deklaration aller genutzten ioctl-Busdrähte
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wr;

// INSTANZ-UPGRADE: Der hps_io Block holt die Ladekanäle fehlerfrei ab!
hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),                  // Nur für OSD-spezifische Maskierung fixiert
	.ps2_key(ps2_key),
	
	// Korrektur: Nur die real existierenden ioctl-Pforten belegen!
	.ioctl_download(ioctl_download),
	.ioctl_index   (ioctl_index),
	.ioctl_addr    (ioctl_addr),
	.ioctl_dout    (ioctl_dout),
	.ioctl_wr      (ioctl_wr)
);

wire clk_sys;
wire ce_pix; 

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

// KORREKTUR BIT-ANBINDUNG: Sichert den 1-Bit Pfad und trennt ungenutzten Ballast!
wire reset = RESET | status[0] | buttons[1];
wire [7:0] core_r;
wire [7:0] core_g;
wire [7:0] core_b;
wire HBlank;
wire HSync;
wire VBlank;
wire VSync;

// =========================================================================
// INTERNE IOCTL-STEUERWEICHEN (SPLITTUNG NACH INDEX-ID)
// =========================================================================
wire ioctl_ks_download   = (ioctl_download && ioctl_index == 8'd0); // Kickstart ROM
wire ioctl_fdd_download  = (ioctl_download && ioctl_index == 8'd1); // Floppy DF0
wire ioctl_hdf0_download = (ioctl_download && ioctl_index == 8'd2); // HDF0
wire ioctl_hdf1_download = (ioctl_download && ioctl_index == 8'd3); // HDF1
wire ioctl_hdf2_download = (ioctl_download && ioctl_index == 8'd4); // HDF2
wire ioctl_hdf3_download = (ioctl_download && ioctl_index == 8'd5); // HDF3

// =========================================================================
// INSTANZIIERUNG DES NEXT-GEN AMIGA MAINBOARDS
// =========================================================================
A1200_top my_amiga_1200
(
	.clk_sys           (clk_sys),
	.reset             (reset),
	.pal_mode          (status[2]),                   // KORREKTUR: Übergibt das exakte TV-Mode Bit 2!
	.ce_pix            (ce_pix),
	
	// Videoschiene
	.HBlank            (HBlank),
	.HSync             (HSync),
	.VBlank            (VBlank),
	.VSync             (VSync),
	.video_r           (core_r),
	.video_g           (core_g),
	.video_b           (core_b),
	
	// USB-Tastatur-Reset an die Hauptplatine (Sicher an reset gekoppelt)
	.kbd_clk           (1'b1), 
	.kbd_data          (1'b1),
	.kbd_reset         (reset), 
	.mouse_x           (2'b00),
	.mouse_y           (2'b00),
	.mouse_btn         (2'b00),
	
	// Gemeinsam genutzte Bus-Infrastruktur für den IOCTL-Ladekanal
	.ioctl_addr        (ioctl_addr),
	.ioctl_data        (ioctl_dout), 
	.ioctl_wr          (ioctl_wr),
	
	// Die dedizierten Download-Flags steuern die Ziel-BRAMs krisensicher an!
	.ioctl_ks_download (ioctl_ks_download),
	.ioctl_fdd_download(ioctl_fdd_download),
	.ioctl_hdf0_download(ioctl_hdf0_download),
	.ioctl_hdf1_download(ioctl_hdf1_download),
	.ioctl_hdf2_download(ioctl_hdf2_download),
	.ioctl_hdf3_download(ioctl_hdf3_download)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_DE    = ~(HBlank | VBlank);
assign VGA_HS    = HSync;
assign VGA_VS    = VSync;
assign VGA_R     = core_r; 
assign VGA_G     = core_g; 
assign VGA_B     = core_b; 

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 

assign LED_USER    = act_cnt  ? act_cnt[25:18]  > act_cnt[7:0]  : act_cnt[25:18]  <= act_cnt[7:0];

endmodule
