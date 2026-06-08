library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Einbindung des globalen CPU-Wörterbuchs
use work.M68020_pkg.all;

entity M68020_fetch is
    Port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        
        -- Schnittstelle zur CPU-Hauptsteuerung
        pc_in        : in  std_logic_vector(31 downto 0); -- Aktueller Programmzähler
        pipe_hold    : in  std_logic;                     -- Friert die Pipeline bei Bedarf ein
        pipe_flush   : in  std_logic;                     -- Leert die Pipeline (z.B. bei Sprungbefehlen)

        -- Originale Ausgänge zu den nachfolgenden Stufen des 68020
        stage_b      : out std_logic_vector(15 downto 0); -- Befehlsabruf (Fetch Stage)
        stage_c      : out std_logic_vector(15 downto 0); -- Befehlsdekodierung (Decode Stage)
        stage_d      : out std_logic_vector(15 downto 0)  -- Ausführung (Execute Stage)
    );
end M68020_fetch;

architecture Behavioral of M68020_fetch is

    -- 1. Deklaration des universellen BRAMs für den internen Cache
    component bram is
        generic (
            ADDR_WIDTH_A : integer := 6;
            ADDR_WIDTH_B : integer := 8;
            DATA_WIDTH   : integer := 32
        );
        port (
            clk_a  : in  std_logic;
            we_a   : in  std_logic;
            addr_a : in  std_logic_vector(ADDR_WIDTH_A - 1 downto 0);
            din_a  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
            dout_a : out std_logic_vector(DATA_WIDTH - 1 downto 0);
            clk_b  : in  std_logic;
            we_b   : in  std_logic;
            addr_b : in  std_logic_vector(ADDR_WIDTH_B - 1 downto 0);
            din_b  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
            dout_b : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    -- Interne Signale für den BRAM-Zugriff (Port A)
    signal cache_addr : std_logic_vector(5 downto 0);
    signal cache_dout : std_logic_vector(31 downto 0);

    -- Die originalen Pipeline-Register des 68020
    signal reg_stage_b : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_stage_c : std_logic_vector(15 downto 0) := (others => '0');
    signal reg_stage_d : std_logic_vector(15 downto 0) := (others => '0');

begin

    -- Wir mappen die unteren Bits des PCs auf die Adresszeilen des Cache-BRAMs
    cache_addr <= pc_in(7 downto 2);

    -- 2. Instanziierung: Das BRAM wird als interner Cache eingebettet
    internal_cache : bram
    generic map (
        ADDR_WIDTH_A => 6, -- 64 Wörter à 32-Bit = 256 Byte (Originalgröße 68020)
        ADDR_WIDTH_B => 8, -- Vorerst ungenutzt
        DATA_WIDTH   => 32
    )
    port map (
        clk_a  => clk,
        we_a   => '0', -- Vorerst nur Lesen über Port A, Befüllen kommt mit dem Bus-Controller
        addr_a => cache_addr,
        din_a  => (others => '0'),
        dout_a => cache_dout,
        
        -- Port B bleibt wie vereinbart komplett isoliert und inaktiv für spätere Zwecke
        clk_b  => clk,
        we_b   => '0',
        addr_b => (others => '0'),
        din_b  => (others => '0'),
        dout_b => open
    );

    -- 3. Die originale Pipeline-Zustandslogik des Motorola 68020
    process(clk, reset)
    begin
        if reset = '1' then
            reg_stage_b <= OP_NOP; -- Bei Reset wird die Pipeline mit NOPs gefüllt
            reg_stage_c <= OP_NOP;
            reg_stage_d <= OP_NOP;
        elsif rising_edge(clk) then
            if pipe_flush = '1' then
                -- Pipeline leeren bei Sprüngen (Branches / Jumps)
                reg_stage_b <= OP_NOP;
                reg_stage_c <= OP_NOP;
                reg_stage_d <= OP_NOP;
            elsif pipe_hold = '0' then
                -- Normaler Vorlese-Zyklus (Prefetch-Mechanismus): 
                -- Daten rücken eine Stufe weiter, während neue Daten aus dem Cache kommen.
                reg_stage_d <= reg_stage_c;
                reg_stage_c <= reg_stage_b;
                
                -- Da das BRAM 32-Bit liefert, entscheidet das Bit PC(1), 
                -- welches 16-Bit-Befehlswort in Stage B geladen wird.
                if pc_in(1) = '0' then
                    reg_stage_b <= cache_dout(31 downto 16);
                else
                    reg_stage_b <= cache_dout(15 downto 0);
                end if;
            end if;
        end if;
    end process;

    -- Zuweisung an die Ausgangs-Pins des Moduls
    stage_b <= reg_stage_b;
    stage_c <= reg_stage_c;
    stage_d <= reg_stage_d;

end Behavioral;
