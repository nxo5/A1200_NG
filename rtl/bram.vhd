library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bram is
    generic (
        ADDR_WIDTH_A : integer := 6;   -- 64 Einträge à 32-Bit für den CPU-Cache
        ADDR_WIDTH_B : integer := 8;   -- Vorerst inaktiv reserviert
        DATA_WIDTH   : integer := 32
    );
    port (
        -- Port A (Direkt in der CPU für den Befehlscache eingebettet)
        clk_a  : in  std_logic;
        we_a   : in  std_logic;
        addr_a : in  std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
        din_a  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        dout_a : out std_logic_vector(DATA_WIDTH - 1 downto 0);
        
        -- Port B (Isoliert nach außen für spätere Zwecke)
        clk_b  : in  std_logic;
        we_b   : in  std_logic;
        addr_b : in  std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
        din_b  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        dout_b : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end bram;

architecture Behavioral of bram is
    -- Die maximale Tiefe wird anhand der größeren Adressbreite berechnet
    constant MAX_DEPTH : integer := 2**ADDR_WIDTH_B;
    
    -- Definition des Speichers als Array
    type memory_t is array (0 to MAX_DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    
    -- Der eigentliche Speicherblock als geschütztes VHDL-Signal statt "shared variable"
    signal ram_block : memory_t := (others => (others => '0'));

begin

    -- =================================================================
    -- PORT A: SYNCHRONER ZUGRIFF MIT EXAKT 1 TAKT LATENZ
    -- =================================================================
    process(clk_a)
    begin
        if rising_edge(clk_a) then
            if we_a = '1' then
                ram_block(to_integer(unsigned(addr_a))) <= din_a;
            end if;
            -- Zyklusgenaues Vorladen der Daten für den nächsten Takt
            dout_a <= ram_block(to_integer(unsigned(addr_a)));
        end if;
    end process;

    -- =================================================================
    -- PORT B: SYNCHRONER ZUGRIFF MIT EXAKT 1 TAKT LATENZ
    -- =================================================================
    process(clk_b)
    begin
        if rising_edge(clk_b) then
            if we_b = '1' then
                ram_block(to_integer(unsigned(addr_b))) <= din_b;
            end if;
            dout_b <= ram_block(to_integer(unsigned(addr_b)));
        end if;
    end process;

end Behavioral;
