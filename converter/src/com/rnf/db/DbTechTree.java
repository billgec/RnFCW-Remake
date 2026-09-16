package com.rnf.db;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;

/**
 * Reader for {@code db\dbtechtree.dat}. Unlike the other tables this one is
 * <em>not</em> a "count + fixed records" file: its entries sit at irregular
 * offsets with variable-length appendices between them, so they have to be
 * found by pattern instead of by index.
 *
 * <p>The pattern (verified byte-by-byte, see the original
 * {@code docs/FORMATS.md}): an entry is 44 consecutive {@code u32}s
 * whose field {@code [2]} is always {@code 14}. Within it:
 *
 * <ul>
 *   <li>{@code [0]} the ID this entry is about - the same value as the
 *       object's {@code dbobjects +912} for a trainable unit, or the tech ID
 *       for a research. Building command panels reference exactly these.</li>
 *   <li>{@code [1]} entry kind/level: {@code 5} for a unit (documented as
 *       "level + 4", so a level-1 unit reads 5), {@code 6} and up for
 *       researches ({@code 6} = the first upgrade step, {@code 7} the second...)</li>
 *   <li>{@code [11]} the <b>prerequisite</b>: the tech ID that has to be
 *       researched first, or {@code 0} for "available from the start". This
 *       is what makes a fresh barracks show level-1 units and step-1
 *       upgrades instead of all five levels at once.</li>
 *   <li>{@code [7]} build/train time. Not seconds: a citizen reads 35, a
 *       swordsman 55, cavalry 150, a tower 200 - the ratios look right for an
 *       RTS but the absolute numbers do not, so {@code com.rnf.world.TrainingQueue}
 *       reads them as ticks and divides. Buildings a worker puts up read 0.</li>
 *   <li>{@code [10]} cost - 19000 for a swordsman, 25000 for a citizen,
 *       105000 for a tower. Scaled by some factor, and possibly packing more
 *       than one resource; nothing in this project spends it yet.</li>
 *   <li>{@code [15]} the object's <b>record index</b> in {@code dbobjects.dat}
 *       (as opposed to {@code [0]}, which is its ID). Confirmed against all
 *       four of the Greek barracks' trainable units; earlier notes
 *       had this one down as "unit-specific ID, meaning unclear".</li>
 *   <li>{@code [16]} index into {@code db\dbButtons.dat} - icon + panel cell</li>
 * </ul>
 *
 * <p>A research's display name is not inside the 44-word entry; it sits in
 * the 100 bytes immediately <em>before</em> it (units carry their name in
 * their {@code dbobjects} record instead, which is where {@link DbObjects}
 * reads it from).
 */
public final class DbTechTree {

    private static final int ENTRY_WORDS = 44;
    private static final int NAME_BYTES_BEFORE = 100;

    /** {@code prerequisiteId == 0} means "no prerequisite - available immediately". */
    public record Entry(int id, String name, int kind, int prerequisiteId, int buildTimeTicks,
                        int cost, int objectRecordIndex, int buttonIndex, int fileOffset, int wood) {}

    private final Map<Integer, Entry> byId;

    private DbTechTree(Map<Integer, Entry> byId) {
        this.byId = byId;
    }

    public static DbTechTree parse(byte[] data) {
        ByteBuffer buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        Map<Integer, Entry> byId = new HashMap<>();
        // Step in u32s from the first position that can still hold a whole entry plus
        // the name block in front of it. First match for an ID wins: the same integer
        // value does turn up in unrelated data (the appendix lists cross-reference IDs
        // too), but those windows fail the [2]==14 test - and where they do not, the
        // real entry is the one whose preceding 100 bytes hold a plausible name, which
        // is also the earliest one for every ID checked so far.
        for (int off = NAME_BYTES_BEFORE; off + ENTRY_WORDS * 4 <= data.length; off += 4) {
            if (buf.getInt(off + 2 * 4) != 14) continue;
            int id = buf.getInt(off);
            if (byId.containsKey(id)) continue;
            byId.put(id, new Entry(id,
                    nameBefore(data, off),
                    buf.getInt(off + 4),
                    buf.getInt(off + 11 * 4),
                    buf.getInt(off + 7 * 4),
                    buf.getInt(off + 10 * 4),
                    buf.getInt(off + 15 * 4),
                    buf.getInt(off + 16 * 4),
                    off,
                    buf.getInt(off + 5 * 4)));
        }
        return new DbTechTree(byId);
    }

    private static String nameBefore(byte[] data, int entryOffset) {
        int base = entryOffset - NAME_BYTES_BEFORE;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < NAME_BYTES_BEFORE; i++) {
            byte b = data[base + i];
            if (b == 0) break;
            if (b < 0x20 || b > 0x7e) break;
            sb.append((char) b);
        }
        return sb.toString();
    }

    /** Null if nothing in the tech tree is keyed to this ID. */
    public Entry byId(int id) {
        return byId.get(id);
    }

    public int size() {
        return byId.size();
    }
}
