-- =========================================================================
-- Projekt: A1200_NG
-- Datei:   030_ec_dec_move.vhd
-- Funktion: Der übergeordnete MOVE-Decoder-Wrapper des 68EC030.
--           Instanziiert den Opcode-Klassifizierer und den Size-Extraktor.
--           Steuert die zyklustreue Befehls-Freigabe an das Rechenwerk.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_030_ec_dec_move is
    Port (
        -- Takt und System-Zustand
        CLK             : in    std_logic;
        RESET_N         : in    std_logic;

        -- Schnittstelle nach außen zum Top-Decoder
        move_en         : in    std_logic;                      -- Freigabe dieses Decoders
        opcode          : in    std_logic_vector(15 downto 0);  -- Aktueller Opcode aus der Pipeline
        
        -- Schnittstelle zum effektiven Adress-Decoder (EA-Modul)
        ea_calc_start   : out   std_logic;                      -- Trigger an EA-Modul senden
        ea_mode         : out   std_logic_vector(2 downto 0);   -- Geforderter EA-Modus
        ea_reg          : out   std_logic_vector(2 downto 0);   -- Gefordertes EA-Register
        ea_ready        : in    std_logic;                      -- EA-Modul meldet: Adresse berechnet
        ea_final_addr   : in    std_logic_vector(31 downto 0);  -- Berechnete physikalische Adresse
        ea_is_register  : in    std_logic;                      -- EA zeigt direkt auf ein Register
        
        -- Schnittstelle zur Bus Interface Unit (BIU)
        move_size       : out   std_logic_vector(1 downto 0);   -- Operationsbreite (00=B, 01=W, 10=L)
        move_bus_req    : out   std_logic;                      -- Bus-Zyklus anfordern
        move_bus_write  : out   std_logic;                      -- '1' = Schreiben, '0' = Lesen
        
        -- Schnittstelle zum Rechenwerk (ALU)
        move_alu_op     : out   std_logic_vector(7 downto 0);   -- Operations-ID für das Rechenwerk
        move_src_reg    : out   std_logic_vector(3 downto 0);   -- Quellregister-Auswahl
        move_dst_reg    : out   std_logic_vector(3 downto 0);   -- Zielregister-Auswahl
        move_ready      : out   std_logic                       -- Befehl komplett fertig ausgeführt
    );
end cpu_030_ec_dec_move;

architecture structural of cpu_030_ec_dec_move is

    -- =====================================================================
    -- KOMPONENTENDEKLARATIONEN DER NEUEN UNTERMODULE
    -- =====================================================================
    component cpu_030_ec_dec_move_op
        Port (
            opcode          : in    std_logic_vector(15 downto 0);
            move_en         : in    std_logic;
            ea_calc_start   : out   std_logic;
            ea_mode         : out   std_logic_vector(2 downto 0);
            ea_reg          : out   std_logic_vector(2 downto 0);
            move_bus_req    : out   std_logic;
            move_bus_write  : out   std_logic;
            move_alu_op     : out   std_logic_vector(7 downto 0);
            move_src_reg    : out   std_logic_vector(3 downto 0);
            move_dst_reg    : out   std_logic_vector(3 downto 0)
        );
    end component;

    component cpu_030_ec_dec_move_size
        Port (
            opcode          : in    std_logic_vector(15 downto 0);
            move_en         : in    std_logic;
            move_size       : out   std_logic_vector(1 downto 0)
        );
    end component;

    -- Interne Logikleitungen zur Verbindung der Bausteine
    signal sub_bus_req      : std_logic;
    signal sub_bus_write    : std_logic;
    signal sub_alu_op       : std_logic_vector(7 downto 0);
    signal sub_src_reg      : std_logic_vector(3 downto 0);
    signal sub_dst_reg      : std_logic_vector(3 downto 0);
    signal sub_size         : std_logic_vector(1 downto 0);

begin

    -- Durchreichen der extrahierten Bitbreite an den Ausgang
    move_size <= sub_size;

    -- =====================================================================
    -- INSTANZIIERUNG: Der kombinatorische Opcode-Klassifizierer
    -- =====================================================================
    i_move_op_decoder : cpu_030_ec_dec_move_op
        port map (
            opcode          => opcode,
            move_en         => move_en,
            ea_calc_start   => ea_calc_start,
            ea_mode         => ea_mode,
            ea_reg          => ea_reg,
            move_bus_req    => sub_bus_req,
            move_bus_write  => sub_bus_write,
            move_alu_op     => sub_alu_op,
            move_src_reg    => sub_src_reg,
            move_dst_reg    => sub_dst_reg
        );

    -- =====================================================================
    -- INSTANZIIERUNG: Die kombinatorische Größen-Extraktion
    -- =====================================================================
    i_move_size_decoder : cpu_030_ec_dec_move_size
        port map (
            opcode          => opcode,
            move_en         => move_en,
            move_size       => sub_size
        );

    -- =====================================================================
    -- SYNCHRONER ABLAUF-PROZESS: Befehlsausführung synchron takten
    -- =====================================================================
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            move_ready     <= '0';
            move_bus_req   <= '0';
            move_bus_write <= '0';
            move_alu_op    <= (others => '0');
            move_src_reg   <= (others => '0');
            move_dst_reg   <= (others => '0');
            
        elsif rising_edge(CLK) then
            move_ready     <= '0';
            move_bus_req   <= '0';
            move_bus_write <= '0';
            
            if move_en = '1' then
                -- Warten, bis das EA-Modul die Quell-/Ziel-Adresse stabil berechnet hat
                if ea_ready = '1' or ea_is_register = '1' then
                    -- Parameter taktgenau an das Rechenwerk (ALU) übergeben
                    move_alu_op    <= sub_alu_op;
                    move_src_reg   <= sub_src_reg;
                    move_dst_reg   <= sub_dst_reg;
                    
                    -- Bus-Zugriffsparameter an die BIU durchreichen
                    move_bus_req   <= sub_bus_req;
                    move_bus_write <= sub_bus_write;
                    
                    -- Befehl im selben Takt als erfolgreich ausgeführt quittieren
                    move_ready     <= '1';
                end if;
            end if;
        end if;
    end process;

end structural;
