package com.rnf.assets;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * The two things this project needs out of a {@code units\*.udf} object
 * definition: which mesh the object renders as, and which skin goes on it.
 *
 * <p>The format is a self-describing tagged binary ({@code USTRB} magic) whose
 * full per-entry layout resisted two earlier attempts - it mixes inline values
 * with name references in a way that is not one uniform tuple shape (see the
 * roadmap notes in README.md). This does not try again. It reads the file's
 * printable strings in order and picks two of them by a rule that holds across
 * every definition checked - infantry, archers, cavalry, citizens, siege crew
 * and the barracks:
 *
 * <pre>
 *   USTRB | &lt;object name&gt; | &lt;...MODEL...&gt; | &lt;skin texture&gt; | &lt;shader&gt; | &lt;sounds&gt; ...
 * </pre>
 *
 * i.e. the model is the first string with {@code MODEL} in it, and the skin is
 * the string right after it. Both are bare names; the files are
 * {@code models\<name>.gr2} and {@code textures\<name>.dds}.
 *
 * <p>This is deliberately a narrow reading of a format that is only partly
 * understood, not a parser. It is worth the shortcut because it replaces
 * guessing from filename conventions, which is demonstrably unreliable here -
 * the naming is not regular across civilizations (Rome
 * {@code men_yrsword_l1_model}, Egypt {@code men_yesword_model_l1}), and the
 * ladder crew's skin is not named after its model at all
 * ({@code men_yMladderguy_MODEL_02} wears {@code men_yMsiegecrew_02T}).
 */
public record UnitDefinition(String modelPath, String texturePath) {

    private static final int MIN_STRING = 5;

    /** @param definitionName the bare name from {@code dbgraphics +100}, no path or extension */
    public static UnitDefinition load(DataSsaArchive archive, String definitionName) throws IOException {
        byte[] bytes = archive.readFile("units\\" + definitionName + ".udf");
        List<String> strings = printableStrings(bytes, 12); // the names are all near the top

        for (int i = 0; i < strings.size() - 1; i++) {
            if (!strings.get(i).toUpperCase().contains("MODEL")) continue;
            return new UnitDefinition(
                    "models\\" + strings.get(i) + ".gr2",
                    "textures\\" + strings.get(i + 1) + ".dds");
        }
        // Some ambient objects (gold mine) name the model after the definition itself.
        String direct = "models\\" + definitionName + ".gr2";
        if (archive.contains(direct) && strings.size() > 2) {
            return new UnitDefinition(direct, "textures\\" + strings.get(2) + ".dds");
        }
        throw new IOException("units\\" + definitionName + ".udf: no MODEL entry among "
                + strings.size() + " leading strings");
    }

    private static List<String> printableStrings(byte[] data, int limit) {
        List<String> out = new ArrayList<>();
        int runStart = -1;
        for (int i = 0; i <= data.length && out.size() < limit; i++) {
            boolean printable = i < data.length && data[i] >= 0x20 && data[i] <= 0x7e;
            if (printable) {
                if (runStart < 0) runStart = i;
            } else if (runStart >= 0) {
                if (i - runStart >= MIN_STRING) {
                    out.add(new String(data, runStart, i - runStart, java.nio.charset.StandardCharsets.US_ASCII));
                }
                runStart = -1;
            }
        }
        return out;
    }
}
