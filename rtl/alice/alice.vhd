library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alice is
    Port (
        -- =============================================================
        -- 1. PHYSIKALISCHE MASTER-TAKTE VOM FPGA (EINGÄNGE)
        -- =============================================================
        clk_sys       : in    std_logic; -- Haupttakt vom FPGA-Board (50 MHz / 114 MHz)
        reset         : in    std_logic; -- Globaler System-Reset
        pal_mode      : in    std_logic; -- '1' für PAL, '0' für NTSC
        
        -- =============================================================
        -- 2. SCHNITTSTELLE ZUM EXTERNEN AMIGA-BUS (AUSGÄNGE FÜR DIE PLATINE)
        -- =============================================================
        clk_amiga     : out   std_logic; -- Der generierte ~14,18 MHz Systemtakt
        clk_cpu       : out   std_logic; -- Der kontrollierbare CPU-Arbeitstakt
        e_clock_ce    : out   std_logic; -- Das Takt-Enable für die 8-Bit-CIAs (~1,418 MHz)
        
        -- Physische Videosynchronisations-Leitungen direkt zum Monitor-Ausgang
        hblank        : out   std_logic; 
        hsync         : out   std_logic; 
        vblank        : out   std_logic; 
        vsync         : out   std_logic; 
        ce_pix        : out   std_logic; -- Pixelclock für das Video-Framework
        
        -- =============================================================
        -- 3. INTERNE BUS-ANBINDUNG AN DEN GEMEINSAMEN CUSTOM-REG-RAUM
        -- =============================================================
        am_addr       : in    std_logic_vector(11 downto 0); -- Registeradresse ($DFF000 bis $DFFFXX)
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten von der CPU
        am_data_r     : out   std_logic_vector(31 downto 0); -- Lesedaten zurück zur CPU
        am_cs_n       : in    std_logic;                     -- Custom-Chip Select
        am_rw         : in    std_logic;                     -- Read (1) / Write (0)
        
        -- =============================================================
        -- 4. SCHNITTSTELLE ZUM SD-RAM (CHIP-RAM-VERBINDUNG)
        -- =============================================================
        dma_req       : out   std_logic;
        dma_rw        : out   std_logic;
        dma_addr      : out   std_logic_vector(31 downto 0);
        dma_data_i    : in    std_logic_vector(31 downto 0); -- Datenlesepfad vom RAM
        dma_data_o    : out   std_logic_vector(31 downto 0)  -- Datenschreibpfad zum RAM
    );
end alice;

architecture Behavioral of alice is

    -- -----------------------------------------------------------------
    -- DEKLARATION DER FÜNF INTERNEN ALICE-KERNE
    -- -----------------------------------------------------------------
    component alice_clk is
        Port (
            clk_sys       : in    std_logic;
            reset         : in    std_logic;
            clk_amiga     : out   std_logic;
            clk_cpu       : out   std_logic;
            e_clock_ce    : out   std_logic;
            cck_tick      : out   std_logic;
            ce_pix        : out   std_logic;
            dma_cpu_hold  : in    std_logic;
            clk_ctrl_reg  : in    std_logic_vector(7 downto 0)
        );
    end component;

    component alice_beam is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            cck_tick      : in    std_logic;
            pal_mode      : in    std_logic;
            hblank        : out   std_logic;
            hsync         : out   std_logic;
            vblank        : out   std_logic;
            vsync         : out   std_logic;
            h_pos         : out   unsigned(8 downto 0);
            v_pos         : out   unsigned(8 downto 0)
        );
    end component;

    component alice_regs is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            internal_addr : in    std_logic_vector(11 downto 0);
            internal_data_w: in   std_logic_vector(31 downto 0);
            chip_sel      : in    std_logic;
            read_en       : in    std_logic;
            write_en      : in    std_logic;
            internal_data_r: out  std_logic_vector(31 downto 0);
            dma_enable_reg: out   std_logic_vector(15 downto 0);
            int_enable_reg: out   std_logic_vector(15 downto 0);
            h_pos_tick    : in    unsigned(8 downto 0);
            v_pos_tick    : in    unsigned(8 downto 0);
            blt_done      : in    std_logic -- Neu deklariert
        );
    end component;

    component alice_dma is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            dma_enable_reg: in    std_logic_vector(15 downto 0);
            h_pos_tick    : in    unsigned(8 downto 0);
            v_pos_tick    : in    unsigned(8 downto 0);
            dma_cpu_hold  : out   std_logic;
            internal_dma_req  : out   std_logic;
            internal_dma_rw   : out   std_logic;
            internal_dma_addr : out   std_logic_vector(31 downto 0);
            blt_dma_req   : in    std_logic;
            blt_dma_rw    : in    std_logic;
            blt_dma_addr  : in    std_logic_vector(31 downto 0);
            blt_granted   : out   std_logic;
            cop_dma_req   : in    std_logic;
            cop_dma_addr  : in    std_logic_vector(31 downto 0);
            cop_granted   : out   std_logic
        );
    end component;

    component alice_mmu is
        Port (
            addr_in       : in    std_logic_vector(31 downto 0);
            mem_req       : in    std_logic;
            chipram_mask  : in    std_logic_vector(31 downto 0);
            chipram_hit   : out   std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- DEKLARATION DER BEIDEN CO-PROZESSOR-KERNE
    -- -----------------------------------------------------------------
    component blitter is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            am_addr       : in    std_logic_vector(11 downto 0);
            am_data_w     : in    std_logic_vector(31 downto 0);
            am_data_r     : out   std_logic_vector(31 downto 0);
            am_reg_write  : in    std_logic;
            blt_done      : out   std_logic;
            blt_zero      : out   std_logic;
            dma_data_in   : in    std_logic_vector(15 downto 0);
            dma_data_out  : out   std_logic_vector(15 downto 0);
            blt_dma_req   : out   std_logic;
            blt_dma_rw    : out   std_logic;
            blt_dma_addr  : out   std_logic_vector(31 downto 0);
            dma_granted   : in    std_logic
        );
    end component;

    component copper is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            am_addr       : in    std_logic_vector(11 downto 0);
            am_data_w     : in    std_logic_vector(31 downto 0);
            cop_reg_write : out   std_logic;
            cop_reg_addr  : out   std_logic_vector(11 downto 0);
            cop_reg_data  : out   std_logic_vector(15 downto 0);
            beam_h_pos    : in    unsigned(8 downto 0);
            beam_v_pos    : in    unsigned(8 downto 0);
            blitter_done  : in    std_logic;
            cop_dma_req   : out   std_logic;
            cop_dma_addr  : out   std_logic_vector(31 downto 0);
            dma_granted   : in    std_logic;
            dma_data_in   : in    std_logic_vector(31 downto 0);
            -- HIER REPARIERT: Das fehlende Gattertor nachgerüstet!
            move_illegal  : out   std_logic
				);
    end component;

    -- -----------------------------------------------------------------
    -- CHIPINTERNE KUPFERBAHNEN (SIGNALE)
    -- -----------------------------------------------------------------
    -- Master-Taktleitungen aus dem Taktwerk
    signal int_clk_amiga    : std_logic;
    signal int_cck_tick     : std_logic;
    signal int_dma_cpu_hold : std_logic;

    -- Live-Video-Koordinaten (Strahlzeiger-Bus)
    signal int_h_pos        : unsigned(8 downto 0);
    signal int_v_pos        : unsigned(8 downto 0);

    -- Systemweite Register-Schalterstellungen (Steuerbusse)
    signal int_dma_enable   : std_logic_vector(15 downto 0);
    signal int_int_enable   : std_logic_vector(15 downto 0);

    -- Bereinigte CPU-Steuersignale für das Registerwerk
    signal int_chip_sel     : std_logic;
    signal int_read_en      : std_logic;
    signal int_write_en     : std_logic;

    -- Lokale Datenleitungen der Adressdekodierung
    signal data_from_regs   : std_logic_vector(31 downto 0);

    -- Vernetzung des internen DMA-Zuteilers (Zentraler Arbitrierungs-Bus)
    signal master_dma_req   : std_logic;
    signal master_dma_rw    : std_logic;
    signal master_dma_addr  : std_logic_vector(31 downto 0);
    signal int_chipram_hit  : std_logic;
    -- NACHHER REPARIERT: Als Konstante definiert – spart Routingwege und tilgt die Warnung! [14.1]
    constant prov_ram_mask   : std_logic_vector(31 downto 0) := x"001FFFFF"; -- Starr 2MB Chip-RAM

    -- Signallinien für den Grafik-Beschleuniger (Blitter-Bus)
    signal int_blt_req      : std_logic;
    signal int_blt_rw       : std_logic;
    signal int_blt_addr     : std_logic_vector(31 downto 0);
    signal int_blt_granted  : std_logic;
    signal int_blt_done     : std_logic;
    signal int_blt_zero     : std_logic;
    signal data_from_blitter : std_logic_vector(15 downto 0);

    -- Signallinien für den programmierbaren Synchron-Coprozessor (Copper-Bus)
    signal int_cop_req      : std_logic;
    signal int_cop_addr     : std_logic_vector(31 downto 0);
    signal int_cop_granted  : std_logic;
    
    -- Register-Schreib-Rückkopplungen vom Copper ins Custom-Registerfeld
    signal cop_to_reg_write : std_logic;
    signal cop_to_reg_addr  : std_logic_vector(11 downto 0);
    signal cop_to_reg_data  : std_logic_vector(15 downto 0);
    
    -- Mux-Signale für den Register-Schreibpfad (Weiche zwischen CPU und Copper)
    signal mux_reg_addr     : std_logic_vector(11 downto 0);
    signal mux_reg_data_w   : std_logic_vector(31 downto 0);
    signal mux_reg_write    : std_logic;
    
    -- Das kombinatorische Hardware-Sperrsignal des Coppers
    signal int_move_illegal : std_logic;

begin

    -- =================================================================
    -- 1. STRUKTURELLE TAKT-, BUS- UND WEICHEN-KOPPLUNG
    -- =================================================================
    -- Den intern generierten Amiga-Frequenzbasistakt an die Platine ausgeben
    clk_amiga <= int_clk_amiga;

    -- Aktivierungssignale direkt aus dem CPU-Bus-Interface ableiten
    int_chip_sel <= '1' when am_cs_n = '0' else '0';
    int_read_en  <= '1' when (am_cs_n = '0' and am_rw = '1') else '0';
    int_write_en <= '1' when (am_cs_n = '0' and am_rw = '0') else '0';

    -- REGISTER-PFAD-WEICHE (MULTIPLEXER)
    mux_reg_addr   <= cop_to_reg_addr  when cop_to_reg_write = '1' else am_addr;
    mux_reg_data_w <= std_logic_vector(resize(unsigned(cop_to_reg_data), 32)) when cop_to_reg_write = '1' else am_data_w;
    
    -- KORREKTUR: Der Schreibimpuls des Coppers wird jetzt rigoros blockiert,
    -- wenn der Copper versucht, ohne CDANG-Freigabe geschützte Register zu beschreiben!
    mux_reg_write  <= '0' when (cop_to_reg_write = '1' and int_move_illegal = '1') else
                      cop_to_reg_write when cop_to_reg_write = '1' else 
                      int_write_en;

    -- DYNAMISCHES CHIP-RAM SPEICHER-ROUTING
    dma_req  <= master_dma_req and int_chipram_hit;
    dma_rw   <= master_dma_rw;
    dma_addr <= master_dma_addr;

    -- Custom-DMA-Schreibzyklus des Blitters filtern
    dma_data_o <= std_logic_vector(resize(unsigned(data_from_blitter), 32)) when master_dma_rw = '0' else (others => '0');

    -- Lesedaten vom internen Registerblock zurück an den CPU-Bus spiegeln
    am_data_r  <= data_from_regs;

    -- =================================================================
    -- 2. CHIP-INTERNE VERDRAHTUNG ALLER MODULE (PORT MAPS)
    -- =================================================================
    
    -- Kern 1: Das zentrale Takt-Schaltwerk und Frequenzteiler
    u_alice_clk : alice_clk
    port map (
        clk_sys       => clk_sys,
        reset         => reset,
        clk_amiga     => int_clk_amiga,
        clk_cpu       => clk_cpu,
        e_clock_ce    => e_clock_ce,
        cck_tick      => int_cck_tick,
        ce_pix        => ce_pix,
        dma_cpu_hold  => int_dma_cpu_hold,
        clk_ctrl_reg  => (others => '0')
    );

    -- Kern 2: Der Strahl- und Video-Synchronzähler
    u_alice_beam : alice_beam
    port map (
        clk_amiga     => int_clk_amiga,
        reset         => reset,
        cck_tick      => int_cck_tick,
        pal_mode      => pal_mode,
        hblank        => hblank,
        hsync         => hsync,
        vblank        => vblank,
        vsync         => vsync,
        h_pos         => int_h_pos,
        v_pos         => int_v_pos
    );

    -- Kern 3: Das Register- und CPU-Interface (Jetzt mit Blitter-Interruptleitung!)
    u_alice_regs : alice_regs
    port map (
        clk_amiga       => int_clk_amiga,
        reset           => reset,
        internal_addr   => mux_reg_addr,
        internal_data_w => mux_reg_data_w,
        chip_sel        => '1',
        read_en         => int_read_en,
        write_en        => mux_reg_write,
        internal_data_r => data_from_regs,
        dma_enable_reg  => int_dma_enable,
        int_enable_reg  => int_int_enable,
        h_pos_tick      => int_h_pos,
        v_pos_tick      => int_v_pos,
        blt_done        => int_blt_done -- Neu fest verdrahtet!
    );

    -- Kern 4: Der Speicher-Zuteiler
    u_alice_dma : alice_dma
    port map (
        clk_amiga         => int_clk_amiga,
        reset             => reset,
        dma_enable_reg    => int_dma_enable,
        h_pos_tick        => int_h_pos,
        v_pos_tick        => int_v_pos,
        dma_cpu_hold      => int_dma_cpu_hold,
        internal_dma_req  => master_dma_req,
        internal_dma_rw   => master_dma_rw,
        internal_dma_addr => master_dma_addr,
        blt_dma_req       => int_blt_req,
        blt_dma_rw        => int_blt_rw,
        blt_dma_addr      => int_blt_addr,
        blt_granted       => int_blt_granted,
        cop_dma_req       => int_cop_req,
        cop_dma_addr      => int_cop_addr,
        cop_granted       => int_cop_granted
    );

    -- Kern 5: Das Memory Management Modul
    u_alice_mmu : alice_mmu
    port map (
        addr_in       => master_dma_addr,
        mem_req       => master_dma_req,
        chipram_mask  => prov_ram_mask,
        chipram_hit   => int_chipram_hit
    );

    -- Co-Chip 1: Der Grafik-Beschleuniger (Blitter)
    u_blitter : blitter
    port map (
        clk_amiga    => int_clk_amiga,
        reset        => reset,
        am_addr      => mux_reg_addr,
        am_data_w    => mux_reg_data_w,
        am_data_r    => open,
        am_reg_write => mux_reg_write,
        blt_done     => int_blt_done,
        blt_zero     => int_blt_zero,
        dma_data_in  => dma_data_i(15 downto 0),
        dma_data_out => data_from_blitter,
        blt_dma_req  => int_blt_req,
        blt_dma_rw   => int_blt_rw,
        blt_dma_addr => int_blt_addr,
        dma_granted  => int_blt_granted
    );

    -- Co-Chip 2: Der programmierbare Synchron-Coprozessor (Copper)
    u_copper : copper
    port map (
        clk_amiga     => int_clk_amiga,
        reset         => reset,
        am_addr       => mux_reg_addr,
        am_data_w     => mux_reg_data_w,
        cop_reg_write => cop_to_reg_write,
        cop_reg_addr  => cop_to_reg_addr,
        cop_reg_data  => cop_to_reg_data,
        beam_h_pos    => int_h_pos,
        beam_v_pos    => int_v_pos,
        blitter_done  => int_blt_done,
        cop_dma_req   => int_cop_req,
        cop_dma_addr  => int_cop_addr,
        dma_granted   => int_cop_granted,
        dma_data_in   => dma_data_i,
        
        -- HIER REPARIERT: Verbindet den Schutzleiter mit dem internen Sperrsignal! [14.1]
        move_illegal  => int_move_illegal 
    );

end Behavioral;
