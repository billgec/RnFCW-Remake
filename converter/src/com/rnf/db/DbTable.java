package com.rnf.db;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Shared reader for the original game's {@code db\*.dat} tables. They have no
 * common schema - each table's per-record layout was reverse-engineered
 * separately (see docs/FORMATS.md) - but they do share a container shape:
 * a {@code u32} record count, then that many fixed-size records back to back.
 *
 * <p>Strings inside a record come in two flavours, both covered here:
 * NUL-terminated fixed-width fields at a known offset ({@link #cString}), and
 * "somewhere in this record there is a developer name" ({@link #longestAsciiRun}),
 * which is how {@code dbobjects.dat} entries are identified - their name has no
 * fixed offset, but it is reliably the longest printable run in the record.
 */
public final class DbTable {

    private final ByteBuffer buf;
    public final int recordSize;
    public final int recordCount;

    public DbTable(byte[] data, int recordSize) {
        this.buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        this.recordSize = recordSize;
        int declared = buf.getInt(0);
        int fits = (data.length - 4) / recordSize;
        // Trust the file's own count, but never read past the end - a truncated or
        // patched table should degrade, not throw.
        this.recordCount = Math.max(0, Math.min(declared, fits));
    }

    /** Byte offset of record {@code i} - records start right after the u32 count. */
    public int recordStart(int i) {
        return 4 + i * recordSize;
    }

    /** Signed 32-bit field at {@code offset} inside record {@code i}. */
    public int intAt(int i, int offset) {
        return buf.getInt(recordStart(i) + offset);
    }

    /** NUL-terminated ASCII at {@code offset} inside record {@code i}, at most {@code max} bytes. */
    public String cString(int i, int offset, int max) {
        int base = recordStart(i) + offset;
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < max; k++) {
            byte b = buf.get(base + k);
            if (b == 0) break;
            if (b < 0x20 || b > 0x7e) break;
            sb.append((char) b);
        }
        return sb.toString();
    }

    /**
     * The longest run of printable ASCII (at least {@code minLength} chars) inside
     * record {@code i}. Used for {@code dbobjects.dat}, whose developer-facing name
     * ("A - Inf01 - Sword Infantry (Level 1 Greek)") sits at no fixed offset but is
     * always the longest such run - the same rule used to identify records (tools/rnf_menu.pl).
     */
    public String longestAsciiRun(int i, int minLength) {
        int base = recordStart(i);
        String best = "";
        int runStart = -1;
        for (int k = 0; k <= recordSize; k++) {
            boolean printable = k < recordSize && isPrintable(buf.get(base + k));
            if (printable) {
                if (runStart < 0) runStart = k;
            } else if (runStart >= 0) {
                int len = k - runStart;
                if (len >= minLength && len > best.length()) {
                    best = ascii(base + runStart, len);
                }
                runStart = -1;
            }
        }
        return best;
    }

    private static boolean isPrintable(byte b) {
        return b >= 0x20 && b <= 0x7e;
    }

    private String ascii(int base, int len) {
        char[] c = new char[len];
        for (int k = 0; k < len; k++) c[k] = (char) buf.get(base + k);
        return new String(c);
    }
}
