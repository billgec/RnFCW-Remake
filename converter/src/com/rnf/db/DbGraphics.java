package com.rnf.db;

import java.util.ArrayList;
import java.util.List;

/**
 * Reader for {@code db\dbgraphics.dat} - 2477 records of 212 bytes, one per
 * object, reached from {@code dbobjects +304}. It is the middle link in the
 * chain from a database row to actual geometry:
 *
 * <pre>
 *   dbobjects +304 -> dbgraphics +100 -> units\&lt;name&gt;.udf -> models\*.gr2 + textures\*.dds
 * </pre>
 *
 * <p>{@code +0} repeats the object's developer name, {@code +100} is the name
 * of its {@code .udf} definition (not the {@code .gr2} - that is one more hop,
 * see {@code com.rnf.assets.UnitDefinition}), {@code +204} the record's own
 * index. Layout verified against the original game, whose
 * {@code tools/rnf_gfxmodel.pl} reads and patches the same field.
 */
public final class DbGraphics {

    private static final int RECORD_SIZE = 212;
    private static final int OFF_OBJECT_NAME = 0;
    private static final int OFF_DEFINITION_NAME = 100;

    /** {@code definitionName} is a bare name - {@code units\<name>.udf} is the file. */
    public record Entry(int index, String objectName, String definitionName) {}

    private final List<Entry> entries;

    private DbGraphics(List<Entry> entries) {
        this.entries = entries;
    }

    public static DbGraphics parse(byte[] data) {
        DbTable table = new DbTable(data, RECORD_SIZE);
        List<Entry> out = new ArrayList<>(table.recordCount);
        for (int i = 0; i < table.recordCount; i++) {
            out.add(new Entry(i,
                    table.cString(i, OFF_OBJECT_NAME, 100),
                    table.cString(i, OFF_DEFINITION_NAME, 100)));
        }
        return new DbGraphics(out);
    }

    /** Null for out-of-range indices. */
    public Entry get(int index) {
        return index >= 0 && index < entries.size() ? entries.get(index) : null;
    }

    public int size() {
        return entries.size();
    }
}
