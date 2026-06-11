-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_mux.vhd
-- Teil:    1 von 2 (Entity-Schnittstelle des Weichenwerks)
-- Funktion: Das kombinatorische Bus- & Control-Multiplexer-Modul (68EC030).
--           Schaltet die verteilten Decoder- und FSM-Ausgänge ohne
--           Taktverzögerung auf den zentralen CPU-Core-Bus auf.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_mux is
    Port (
        -- Zustandssignale aus der Master-FSM
        fsm_running_mode    : in    std_logic;
        fsm_bus_req         : in    std_logic;
        fsm_bus_write       : in    std_logic;
        fsm_bus_addr        : in    std_logic_vector(31 downto 0);
        fsm_bus_data_out    : in    std_logic_vector(31 downto 0);
        fsm_bus_type        : in    std_logic_vector(2 downto 0);
        
        -- Aktivitäts-Meldungen des Opcode-Vordecoders
        move_active         : in    std_logic;
        alu_active          : in    std_logic;
        bitfield_active     : in    std_logic;
        special_active      : in    std_logic;
        
        -- Steuersignale aus dem MOVE-Decoder
        bus_req_move        : in    std_logic;
        bus_w_move          : in    std_logic;
        bus_sz_move         : in    std_logic_vector(1 downto 0);
        alu_op_move         : in    std_logic_vector(7 downto 0);
        alu_src_move        : in    std_logic_vector(3 downto 0);
        alu_dst_move        : in    std_logic_vector(3 downto 0);
        
        -- Steuersignale aus dem ALU-Decoder
        bus_req_alu         : in    std_logic;
        bus_w_alu           : in    std_logic;
        alu_op_alu          : in    std_logic_vector(7 downto 0);
        alu_src_alu         : in    std_logic_vector(3 downto 0);
        alu_dst_alu         : in    std_logic_vector(3 downto 0);
        sub_size            : in    std_logic_vector(1 downto 0);
        
        -- Steuersignale aus dem BITFIELD-Decoder
        alu_op_bf           : in    std_logic_vector(7 downto 0);
        
        -- Steuersignale aus dem SPECIAL-Decoder
        bus_req_spec        : in    std_logic;

        -- Zentrale kombinatorische Ausgänge an die BIU (Turbokarten-Bus)
        bus_cycle_start     : out   std_logic;
        bus_cycle_write     : out   std_logic;
        bus_cycle_size      : out   std_logic_vector(1 downto 0);
        bus_cycle_type      : out   std_logic_vector(2 downto 0);
        bus_data_mux_out    : out   std_logic_vector(31 downto 0);
        
        -- Zentrale kombinatorische Ausgänge an das Rechenwerk (ALU/Core)
        alu_opcode          : out   std_logic_vector(7 downto 0);
        alu_size            : out   std_logic_vector(1 downto 0);
        alu_src_reg         : out   std_logic_vector(3 downto 0);
        alu_dst_reg         : out   std_logic_vector(3 downto 0)
    );
end cpu_030_ec_dec_mux;

architecture behavioral of cpu_030_ec_dec_mux is

begin

    -- =====================================================================
    -- KOMBINAOTORISCHES CORE- UND BUS-MULTIPLEXING (0 WAIT-STATES)
    -- =====================================================================
    process(fsm_running_mode, fsm_bus_req, fsm_bus_write, fsm_bus_addr, 
            fsm_bus_data_out, fsm_bus_type, move_active, alu_active, 
            bitfield_active, special_active, bus_req_move, bus_w_move, 
            bus_sz_move, alu_op_move, alu_src_move, alu_dst_move, bus_req_alu, 
            bus_w_alu, alu_op_alu, alu_src_alu, alu_dst_alu, sub_size, alu_op_bf, 
            bus_req_spec)
    begin
        -- Sichere Standardwerte initialisieren, um Latches zu verhindern
        bus_cycle_start  <= '0';
        bus_cycle_write  <= '0';
        bus_cycle_size   <= "01";   -- Word-Standard
        bus_cycle_type   <= "001";  -- User Data Space
        bus_data_mux_out <= (others => '0');
        
        alu_opcode       <= x"00";
        alu_size         <= "01";
        alu_src_reg      <= x"0";
        alu_dst_reg      <= x"0";

        -- WEICHENSTEURUNG: FSM-Sonderzyklen (Boot / Exception) oder Fließband?
        if fsm_running_mode = '0' then
            -- A: DIE MASTER-FSM KONTROLLIERT DEN CORES- UND AUSSENBUS
            bus_cycle_start  <= fsm_bus_req;
            bus_cycle_write  <= fsm_bus_write;
            bus_cycle_size   <= "10"; -- Ausnahmen arbeiten mit 32-Bit Longwords
            bus_cycle_type   <= fsm_bus_type;
            bus_data_mux_out <= fsm_bus_data_out; -- Schreibdaten für den Stack-Push weitergeben
            
        else
            -- B: REGULÄRER FLIESSBAND-BETRIEB NACH OP-CODE KLASSEN
            if move_active = '1' then
                bus_cycle_start <= bus_req_move;
                bus_cycle_write <= bus_w_move;
                bus_cycle_size  <= bus_sz_move;
                bus_cycle_type  <= "001";
                alu_opcode      <= alu_op_move;
                alu_size        <= bus_sz_move;
                alu_src_reg     <= alu_src_move;
                alu_dst_reg     <= alu_dst_move;
                
            elsif alu_active = '1' then
                bus_cycle_start <= bus_req_alu;
                bus_cycle_write <= bus_w_alu;
                bus_cycle_size  <= sub_size;
                bus_cycle_type  <= "001";
                alu_opcode      <= alu_op_alu;
                alu_size        <= sub_size;
                alu_src_reg     <= alu_src_alu;
                alu_dst_reg     <= alu_dst_alu;
                
            elsif bitfield_active = '1' then
                alu_opcode      <= alu_op_bf;
                alu_size        <= "10"; -- Bitfeld-Befehle nutzen starr Longwords
                
            elsif special_active = '1' then
                bus_cycle_start <= bus_req_spec;
                bus_cycle_write <= '1';
                bus_cycle_type  <= "111"; -- CPU Space Cycle für System-Befehle
            end if;
        end if;
    end process;

end behavioral;
