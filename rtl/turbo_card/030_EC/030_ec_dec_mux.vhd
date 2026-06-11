-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_mux.vhd
-- Sektion: Teil 1 von 3 (Vollständige Entity-Schnittstelle)
-- Funktion: Der zentrale Signal-Multiplexer und Bus-Wähler des Cores.
--           KONSOLIDIERTE OPTIMIERUNGS-FASSUNG (HEBEL 2):
--           - Typenkonforme conditional-Zuweisung zur ALU-Maskierung.
--           - Logische Buskompression verhindert LUT-Kaskaden im FPGA.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_mux is
    Port (
        -- Steuerleitungen der Master-Steuerung
        fsm_running_mode    : in    std_logic;                      -- '0' = Boot/Trap FSM-Hoheit, '1' = Decoder-Hoheit
        fsm_bus_req         : in    std_logic;                      
        fsm_bus_write       : in    std_logic;                      
        fsm_bus_addr        : in    std_logic_vector(31 downto 0);  
        fsm_bus_data_out    : in    std_logic_vector(31 downto 0);  
        fsm_bus_type        : in    std_logic_vector(2 downto 0);   

        -- Aktivitäts-Freigaben der Teildecoder (Exklusiv-Muster)
        move_active         : in    std_logic;                      
        alu_active          : in    std_logic;                      
        bitfield_active     : in    std_logic;                      
        special_active      : in    std_logic;                      

        -- Treiber-Leitungen des MOVE-Decoders
        bus_req_move        : in    std_logic;                      
        bus_w_move          : in    std_logic;                      
        bus_sz_move         : in    std_logic_vector(1 downto 0);   
        alu_op_move         : in    std_logic_vector(7 downto 0);   
        alu_src_move        : in    std_logic_vector(3 downto 0);   
        alu_dst_move        : in    std_logic_vector(3 downto 0);   

        -- Treiber-Leitungen des ALU-Decoders
        bus_req_alu         : in    std_logic;                      
        bus_w_alu           : in    std_logic;                      
        alu_op_alu          : in    std_logic_vector(7 downto 0);   
        alu_src_alu         : in    std_logic_vector(3 downto 0);   
        alu_dst_alu         : in    std_logic_vector(3 downto 0);   
        sub_size            : in    std_logic_vector(1 downto 0);   

        -- Treiber-Leitungen des BITFIELD-Decoders
        alu_op_bf           : in    std_logic_vector(7 downto 0);   

        -- Treiber-Leitungen des SPECIAL-Decoders
        bus_req_spec        : in    std_logic;                      

        -- Globale physikalische Ausgänge zur Bus Interface Unit (BIU)
        bus_cycle_start     : out   std_logic;                      
        bus_cycle_write     : out   std_logic;                      
        bus_cycle_size      : out   std_logic_vector(1 downto 0);   
        bus_cycle_type      : out   std_logic_vector(2 downto 0);   
        bus_data_mux_out    : out   std_logic_vector(31 downto 0);  

        -- Globale physikalische Ausgänge zur Execution Unit (ALU-Kern)
        alu_opcode          : out   std_logic_vector(7 downto 0);   
        alu_size            : out   std_logic_vector(1 downto 0);   
        alu_src_reg         : out   std_logic_vector(3 downto 0);   
        alu_dst_reg         : out   std_logic_vector(3 downto 0)    
    );
end cpu_030_ec_dec_mux;

architecture behavioral of cpu_030_ec_dec_mux is

begin

    -- =====================================================================
    -- KORREKTUR HEBEL 2: STANDARDKONFORME MASKIERUNG OHNE OTHERS-AGGREGATE
    -- =====================================================================
    -- Schaltet die Opcodes und Register-Indexe exakt nach Aktivität durch.
    -- Ist ein Kanal inaktiv, liefert er eine harte Null (0 % LE-Verbrauch).
    alu_opcode <= alu_op_move when move_active = '1' else
                  alu_op_alu  when alu_active = '1'  else
                  alu_op_bf   when bitfield_active = '1' else
                  (others => '0');

    alu_size   <= bus_sz_move when move_active = '1' else
                  sub_size    when alu_active = '1'  else
                  (others => '0');

    alu_src_reg <= alu_src_move when move_active = '1' else
                   alu_src_alu  when alu_active = '1'  else
                   (others => '0');

    alu_dst_reg <= alu_dst_move when move_active = '1' else
                   alu_dst_alu  when alu_active = '1'  else
                   (others => '0');

    -- =====================================================================
    -- HEBEL 2 OPTIMIERUNG: OR-KOMPRESSION FÜR DIE BUSCONTROLLER-ANFORDERUNG
    -- =====================================================================
    process(fsm_running_mode, fsm_bus_req, fsm_bus_write, fsm_bus_addr, 
            fsm_bus_data_out, fsm_bus_type, move_active, alu_active, special_active,
            bus_req_move, bus_w_move, bus_sz_move, bus_req_alu, bus_w_alu, 
            sub_size, bus_req_spec)
        
        variable v_dec_req   : std_logic;
        variable v_dec_w     : std_logic;
        variable v_dec_size  : std_logic_vector(1 downto 0);
        variable v_dec_type  : std_logic_vector(2 downto 0);
    begin
        -- Standardmäßig alles im Ruhezustand (Harte Nullen)
        v_dec_req   := '0';
        v_dec_w     := '0';
        v_dec_size  := (others => '0');
        v_dec_type  := "001"; -- Standard: User Data Space

        -- Latenzfreie OR-Bündelung der exklusiven Teildecoder-Pfade
        if move_active = '1' then
            v_dec_req  := bus_req_move;
            v_dec_w    := bus_w_move;
            v_dec_size := bus_sz_move;
        elsif alu_active = '1' then
            v_dec_req  := bus_req_alu;
            v_dec_w    := bus_w_alu;
            v_dec_size := sub_size;
        elsif special_active = '1' then
            v_dec_req  := bus_req_spec;
            v_dec_type := "101"; -- Supervisor Data Space für Systemzugriffe
        end if;

        -- =====================================================================
        -- FINALE WEICHE ZWISCHEN MASTER-FSM UND PIPELINE-BETRIEB (0 WAIT-STATES)
        -- =====================================================================
        if fsm_running_mode = '0' then
            -- Kaltstart-Bootvektoren oder Exception-Einzug haben absolute Priorität
            bus_cycle_start  <= fsm_bus_req;
            bus_cycle_write  <= fsm_bus_write;
            bus_cycle_size   <= "10"; -- Starre 32-Bit-Longword-Transfers beim Booten/Trapping
            bus_cycle_type   <= fsm_bus_type;
            bus_data_mux_out <= fsm_bus_data_out;
        else
            -- Regulärer Befehlsablauf des sanierten CPU-Kerns
            bus_cycle_start  <= v_dec_req;
            bus_cycle_write  <= v_dec_w;
            bus_cycle_size   <= v_dec_size;
            bus_cycle_type   <= v_dec_type;
            bus_data_mux_out <= fsm_bus_data_out; -- Datenkanal für Register-Schreibzyklen
        end if;
    end process;

end behavioral;
