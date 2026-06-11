library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- use work.M68020_pkg.all;

entity blitter is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE (VON ALICE.VHD)
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNES REGISTER-INTERFACE (VON ALICE.VHD)
        -- =============================================================
        -- Der Blitter lauscht auf die CPU-Zugriffe im Bereich $DFF040 bis $DFF07X
        am_addr       : in    std_logic_vector(11 downto 0); -- Custom-Registeradresse
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten der CPU
        am_data_r     : out   std_logic_vector(31 downto 0); -- Lesedaten zurück zur CPU
        am_reg_write  : in    std_logic;                     -- Register-Schreibimpuls
        
        -- Statussignale direkt an die Interrupt- und Statusebene von Alice
        blt_done      : out   std_logic;                     -- '1' = Blitter ist fertig (BLTDONE-Flag)
        blt_zero      : out   std_logic;                     -- '1' = Letzte Operation ergab komplett Null
        
        -- =============================================================
        -- 3. INTERNE DATEN- UND DMA-SCHNITTSTELLEN (VON/ZU ALICE.VHD)
        -- =============================================================
        dma_data_in   : in    std_logic_vector(15 downto 0); -- Vom DMA geladene 16-Bit-Grafikdaten
        dma_data_out  : out   std_logic_vector(15 downto 0); -- Zurückzuschreibende 16-Bit-Grafikdaten
        
        -- DMA-Anforderungen an das zentrale Speicher-Management
        blt_dma_req   : out   std_logic;                     -- Blitter fordert Speicher-Slot an
        blt_dma_rw    : out   std_logic;                     -- '1' = Lesen, '0' = Schreiben
        blt_dma_addr  : out   std_logic_vector(31 downto 0); -- Berechnete 32-Bit Chip-RAM-Adresse
        dma_granted   : in    std_logic                      -- Slot freigegeben
    );
end blitter;

architecture Behavioral of blitter is

    -- -----------------------------------------------------------------
    -- DEKLARATION DER VIER INTERNEN BLITTER-FUNKTIONSBLÖCKE
    -- -----------------------------------------------------------------
    component blitter_addr is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            chan_select   : in    std_logic_vector(1 downto 0);
            ptr_inc       : in    std_logic;
            mod_add       : in    std_logic;
            line_mode_en  : in    std_logic;
            line_sign_bit : in    std_logic;
            blt_dma_addr  : out   std_logic_vector(31 downto 0)
        );
    end component;

    component blitter_shift is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            dma_data_in   : in    std_logic_vector(15 downto 0);
            chan_load     : in    std_logic_vector(1 downto 0);
            is_first_word : in    std_logic;
            is_last_word  : in    std_logic;
            shifted_data_a: out   std_logic_vector(15 downto 0);
            shifted_data_b: out   std_logic_vector(15 downto 0);
            buffered_data_c: out   std_logic_vector(15 downto 0)
        );
    end component;

    component blitter_alu is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            shifted_data_a: in    std_logic_vector(15 downto 0);
            shifted_data_b: in    std_logic_vector(15 downto 0);
            buffered_data_c: in    std_logic_vector(15 downto 0);
            line_mode_en  : in    std_logic;
            alu_calc_tick : in    std_logic;
            line_sign_bit : out   std_logic;
            alu_data_out  : out   std_logic_vector(15 downto 0);
            blitter_zero  : out   std_logic
        );
    end component;

    component blitter_fsm is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            blitter_done  : out   std_logic;
            fsm_chan_sel  : out   std_logic_vector(1 downto 0);
            fsm_ptr_inc   : out   std_logic;
            fsm_mod_add   : out   std_logic;
            fsm_chan_load : out   std_logic_vector(1 downto 0);
            fsm_line_mode : out   std_logic;
            fsm_calc_tick : out   std_logic;
            fsm_first_word: out   std_logic;
            fsm_last_word : out   std_logic;
            fsm_dma_req   : out   std_logic;
            fsm_dma_rw    : out   std_logic;
            dma_granted   : in    std_logic
        );
    end component;

    -- -----------------------------------------------------------------
    -- CHIPINTERNE KUPFERBAHNEN (SIGNALE)
    -- -----------------------------------------------------------------
    -- Steuerleitungen vom Kontrollwerk (FSM) an die Module
    signal int_chan_sel    : std_logic_vector(1 downto 0);
    signal int_ptr_inc     : std_logic;
    signal int_mod_add     : std_logic;
    signal int_chan_load   : std_logic_vector(1 downto 0);
    signal int_line_mode   : std_logic;
    signal int_calc_tick   : std_logic;

    -- Die internen Kupferbahnen für den zeilenweiten Wort-Status
    signal int_first_word  : std_logic;
    signal int_last_word   : std_logic;

    -- NEU: Die internen Kupferbahnen für das Bresenham-Vektor-Getriebe
    signal int_line_sign   : std_logic;

    -- Interne Datenbusse zwischen den Grafik-Blöcken
    signal data_sh_to_alu_a : std_logic_vector(15 downto 0);
    signal data_sh_to_alu_b : std_logic_vector(15 downto 0);
    signal data_sh_to_alu_c : std_logic_vector(15 downto 0);

begin

    -- Provisorisch offener Lesepfad für CPU-Registerabfragen der Blitter-Ebene
    am_data_r <= (others => '0');

    -- =================================================================
    -- CHIP-INTERNE VERDRAHTUNG (PORT MAPS)
    -- =================================================================
    
    -- Block 1: Der Adress- und Zeiger-Generator (Erweitert um Linien-Sign)
    u_blitter_addr : blitter_addr
    port map (
        clk_amiga     => clk_amiga,
        reset         => reset,
        reg_addr      => am_addr,
        reg_data_w    => am_data_w,
        reg_write_en  => am_reg_write,
        chan_select   => int_chan_sel,
        ptr_inc       => int_ptr_inc,
        mod_add       => int_mod_add,
        line_mode_en  => int_line_mode,
        line_sign_bit => int_line_sign, -- Neu verschaltet
        blt_dma_addr  => blt_dma_addr
    );

    -- Block 2: Das Datenpuffer- und Shifter-Zentrum
    u_blitter_shift : blitter_shift
    port map (
        clk_amiga     => clk_amiga,
        reset         => reset,
        reg_addr      => am_addr,
        reg_data_w    => am_data_w,
        reg_write_en  => am_reg_write,
        dma_data_in   => dma_data_in,
        chan_load     => int_chan_load,
        is_first_word => int_first_word, 
        is_last_word  => int_last_word,  
        shifted_data_a=> data_sh_to_alu_a,
        shifted_data_b=> data_sh_to_alu_b,
        buffered_data_c=> data_sh_to_alu_c
    );

    -- Block 3: Die mathematische Logik-Einheit (Erweitert um Linien-Sign)
    u_blitter_alu : blitter_alu
    port map (
        clk_amiga     => clk_amiga,
        reset         => reset,
        reg_addr      => am_addr,
        reg_data_w    => am_data_w,
        reg_write_en  => am_reg_write,
        shifted_data_a=> data_sh_to_alu_a,
        shifted_data_b=> data_sh_to_alu_b,
        buffered_data_c=> data_sh_to_alu_c,
        line_mode_en  => int_line_mode,
        alu_calc_tick => int_calc_tick,
        line_sign_bit => int_line_sign, -- Neu verschaltet
        alu_data_out  => dma_data_out,
        blitter_zero  => blt_zero
    );

    -- Block 4: Das Kontrollwerk und Befehls-FSM
    u_blitter_fsm : blitter_fsm
    port map (
        clk_amiga     => clk_amiga,
        reset         => reset,
        reg_addr      => am_addr,
        reg_data_w    => am_data_w,
        reg_write_en  => am_reg_write,
        blitter_done  => blt_done,
        fsm_chan_sel  => int_chan_sel,
        fsm_ptr_inc   => int_ptr_inc,
        fsm_mod_add   => int_mod_add,
        fsm_chan_load => int_chan_load,
        fsm_line_mode => int_line_mode,
        fsm_calc_tick => int_calc_tick,
        fsm_first_word=> int_first_word, 
        fsm_last_word => int_last_word,  
        fsm_dma_req   => blt_dma_req,
        fsm_dma_rw    => blt_dma_rw,
        dma_granted   => dma_granted
    );

end Behavioral;
