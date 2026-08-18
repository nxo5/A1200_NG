-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   copper.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle und Deklarationen)
-- Funktion: Der programmierbare Synchron-Coprozessor (Copper-Zentrale).
-- KORREKTUR PORT-MISMATCH:
--   - Rüstet move_illegal in der äußeren Entity nach zur Tilgung von Error 12002! [14.1]
--   - Hält alle Takte, Busleitungen und Unterkomponenten fehlerfrei bereit. [14.1]
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity copper is
    Port (
        -- =============================================================
        -- 1. CLOCK- UND RESET-EINGÄNGE (VON ALICE.VHD)
        -- =============================================================
        clk_amiga     : in    std_logic; -- Der synchrone 14,18 MHz Systemtakt
        reset         : in    std_logic; -- Globaler System-Reset
        
        -- =============================================================
        -- 2. INTERNES REGISTER-INTERFACE (VON ALICE.VHD)
        -- =============================================================
        am_addr       : in    std_logic_vector(11 downto 0); -- Custom-Registeradresse
        am_data_w     : in    std_logic_vector(31 downto 0); -- Schreibdaten der CPU
        am_reg_write  : in    std_logic;                     -- Register-Schreibimpuls
        
        -- Ausgänge für Register-Schreibbefehle des Coppers an das System (MOVE-Befehl)
        cop_reg_write : out   std_logic;                     
        cop_reg_addr  : out   std_logic_vector(11 downto 0); -- Zieladresse des MOVE-Befehls ($DFFXXX)
        cop_reg_data  : out   std_logic_vector(15 downto 0); -- 16-Bit Schreibdaten für das Zielregister
        
        -- =============================================================
        -- 3. INTERNE SCHNITTSTELLEN ZU DEN ALICE-BLÖCKEN (VON/ZU ALICE.VHD)
        -- =============================================================
        beam_h_pos    : in    unsigned(8 downto 0);          -- Aktueller H-Strahl
        beam_v_pos    : in    unsigned(8 downto 0);          -- Aktuelle V-Zeile
        
        -- Statussignal vom Blitter für WAIT-Befehle auf Blitter-Ende
        blitter_done  : in    std_logic;                     
        
        -- DMA-Anforderungen an das zentrale Speicher-Management
        cop_dma_req   : out   std_logic;                     
        cop_dma_addr  : out   std_logic_vector(31 downto 0); -- Berechnete 32-Bit Adresse des Befehls
        dma_granted   : in    std_logic;                     -- Slot freigegeben
        dma_data_in   : in    std_logic_vector(31 downto 0); -- Geladene 32-Bit Befehlsdaten aus dem RAM
        
        -- HIER REPARIERT: Ausgang an das übergeordnete Alice-Dach nachgerüstet! [14.1]
        move_illegal  : out   std_logic                      -- Signalisierung illegaler MOVE-Befehle [14.1]
    );
end copper;

architecture Behavioral of copper is

    -- -----------------------------------------------------------------
    -- DEKLARATION DER DREI INTERNEN FUNKTIONSBLÖCKE
    -- -----------------------------------------------------------------
    component copper_dec is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            reg_addr      : in    std_logic_vector(11 downto 0);
            reg_data_w    : in    std_logic_vector(31 downto 0);
            reg_write_en  : in    std_logic;
            dma_inst_word : in    std_logic_vector(31 downto 0);
            load_inst_en  : in    std_logic;
            inst_is_move  : out   std_logic;
            inst_is_wait  : out   std_logic;
            inst_is_skip  : out   std_logic;
            move_target_reg: out  std_logic_vector(11 downto 0);
            move_data_out  : out  std_logic_vector(15 downto 0);
            move_illegal   : out  std_logic;
            wait_h_coord   : out  unsigned(8 downto 0);
            wait_v_coord   : out  unsigned(8 downto 0);
            wait_mask_h    : out  std_logic_vector(8 downto 0);
            wait_mask_v    : out  std_logic_vector(8 downto 0);
            cop_active_pc  : out  unsigned(31 downto 0);        
            fsm_jump_trigger: out std_logic                      
        );
    end component;

    component copper_sync is
        Port (
            beam_h_pos    : in    unsigned(8 downto 0);
            beam_v_pos    : in    unsigned(8 downto 0);
            target_h_pos  : in    unsigned(8 downto 0);
            target_v_pos  : in    unsigned(8 downto 0);
            target_mask_h : in    std_logic_vector(8 downto 0);
            target_mask_v : in    std_logic_vector(8 downto 0);
            blitter_done  : in    std_logic;
            clk_amiga     : in    std_logic; 
            reset         : in    std_logic; 
            position_match: out   std_logic
        );
    end component;

    component copper_fsm is
        Port (
            clk_amiga     : in    std_logic;
            reset         : in    std_logic;
            inst_is_move  : in    std_logic;
            inst_is_wait  : in    std_logic;
            inst_is_skip  : in    std_logic;
            position_match: in    std_logic;
            fsm_jump_trigger : in std_logic;
            fsm_load_inst : out   std_logic;
            fsm_cop_req   : out   std_logic;
            cop_granted   : in    std_logic;
            copper_status : out   std_logic_vector(1 downto 0)
        );
    end component;

	 -- -----------------------------------------------------------------
    -- CHIPINTERNE KUPFERBAHNEN (SIGNALE)
    -- -----------------------------------------------------------------
    signal int_is_move        : std_logic;
    signal int_is_wait        : std_logic;
    signal int_is_skip        : std_logic;
    
    signal int_wait_h         : unsigned(8 downto 0);
    signal int_wait_v         : unsigned(8 downto 0);
    signal int_mask_h         : std_logic_vector(8 downto 0);
    signal int_mask_v         : std_logic_vector(8 downto 0);
    
    signal int_position_match : std_logic;
    signal int_load_inst      : std_logic;
    signal int_cop_status     : std_logic_vector(1 downto 0);

    signal int_copper_pc      : unsigned(31 downto 0);
    signal int_jump_trigger   : std_logic;
    
    signal int_move_illegal   : std_logic;

begin

    -- =================================================================
    -- CHIP-INTERNE VERDRAHTUNG (PORT MAPS)
    -- =================================================================
    
    -- Block 1: Der Befehls-Decoder und Registerpfad
    u_copper_dec : copper_dec
    port map (
        clk_amiga        => clk_amiga,
        reset            => reset,
        reg_addr         => am_addr,
        reg_data_w       => am_data_w,
        reg_write_en     => am_reg_write,
        dma_inst_word    => dma_data_in,
        load_inst_en     => int_load_inst,
        inst_is_move     => int_is_move,
        inst_is_wait     => int_is_wait,
        inst_is_skip     => int_is_skip,
        move_target_reg  => cop_reg_addr,
        move_data_out    => cop_reg_data,
        move_illegal     => int_move_illegal, 
        wait_h_coord     => int_wait_h,
        wait_v_coord     => int_wait_v,
        wait_mask_h      => int_mask_h,
        wait_mask_v      => int_mask_v,
        cop_active_pc    => int_copper_pc,    
        fsm_jump_trigger => int_jump_trigger   
    );

    -- Block 2: Die Synchronisations- und Vergleicher-Matrix (Jetzt voll getaktet)
    u_copper_sync : copper_sync
    port map (
        beam_h_pos      => beam_h_pos,
        beam_v_pos      => beam_v_pos,
        target_h_pos    => int_wait_h,
        target_v_pos    => int_wait_v,
        target_mask_h   => int_mask_h,
        target_mask_v   => int_mask_v,
        blitter_done    => blitter_done,
        clk_amiga       => clk_amiga,       
        reset           => reset,           
        position_match  => int_position_match
    );

    -- Block 3: Die Kontrollwerk-Zustandsmaschine (FSM)
    u_copper_fsm : copper_fsm
    port map (
        clk_amiga        => clk_amiga,
        reset            => reset,
        inst_is_move     => int_is_move,
        inst_is_wait     => int_is_wait,
        inst_is_skip     => int_is_skip,
        position_match   => int_position_match,
        fsm_jump_trigger => int_jump_trigger, 
        fsm_load_inst    => int_load_inst,
        fsm_cop_req      => cop_dma_req,
        cop_granted      => dma_granted,
        copper_status    => int_cop_status
    );

    -- Hardware-Sperre ausführen
    cop_reg_write <= '1' when (int_is_move = '1' and int_cop_status = "10" and int_move_illegal = '0') else '0';

    -- Den berechneten Programmzähler starr an den DMA-Bus von Alice ausgeben
    cop_dma_addr <= std_logic_vector(int_copper_pc);

    -- =====================================================================
    -- KORREKTUR: BRÜCKENSCHALTUNG ZUR ALICE-HAUPTPLATINE [14.1]
    -- Reicht das im Decoder ermittelte MOVE_ILLEGAL-Signal fehlerfrei nach außen weiter! [14.1]
    -- =====================================================================
    move_illegal <= int_move_illegal;

end Behavioral;
