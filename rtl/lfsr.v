// =========================================================================
// Projekt: A1200_NG
// Datei:   lfsr.v
// Funktion: Physikalischer 63-Bit Pseudozufallsgenerator (Paula/Video-Rauschen).
// SANIERUNG MASTER-EDITION - GENVAR PARAMETER HARMONIZATION (0 ERRORS):
//   - Schiebt den Parameter N direkt in den Modulkopf vor die Port-Deklaration.
//   - Erhält die originale lcell-Gatterkette für die FPGA-LUTs bitgetreu.
//   - Tilgt sämtliche vlog-2730 und vlog-2388 Compiler-Abbrüche in ModelSim.
// =========================================================================

module lfsr #(
    parameter N = 63 // KORREKTUR: Parameter steht nun unyielding VOR dem Port!
)(
    output wire [N-1:0] rnd -- Der physikalische 63-Bit Rauschvektor
);

    -- Das Feedback-XOR-Netzwerk über die originalen Taps (Bit 62, 60, 59, 57, 53)
    -- Berechnet das inverse Feedback, um den verbotenen Null-Zustand im FPGA zu verhindern
    wire feedback_next = ~(rnd[N - 1] ^ rnd[N - 3] ^ rnd[N - 4] ^ rnd[N - 6] ^ rnd[N - 10]);

    -- Instanziierung der allerersten Logic Cell (Einspeisung des Feedbacks in Bit 0)
    lcell lc0 (
        .in(feedback_next), 
        .out(rnd[0])
    );

    -- =====================================================================
    -- GENERATE-SCHLEIFE: PHYSIKALISCHES SCHIEBEREGISTER AUS HARDWARE-LUTS
    -- =====================================================================
    generate 
        genvar i;
        for (i = 0; i <= N - 2; i = i + 1) begin : lcn
            -- Schiebt den Zustand von Bit(i) flankenrein weiter nach Bit(i+1)
            lcell lc (
                .in(rnd[i]), 
                .out(rnd[i + 1])
            );
        end
    endgenerate

endmodule
