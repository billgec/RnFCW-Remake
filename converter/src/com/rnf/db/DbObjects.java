package com.rnf.db;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Reader for {@code db\dbobjects.dat} - the master table of every object in
 * the game (units, buildings, props): 3079 records of 2012 bytes each.
 *
 * <p>Only the fields this project actually needs are pulled out. Offsets are
 * the ones verified byte-by-byte against the original game
 * (see {@code docs/FORMATS.md}, section "Database tables" -
 * dbobjects.dat"); the same offsets drive {@code tools/rnf_menu.pl} there,
 * which is what this class is a Java port of.
 *
 * <ul>
 *   <li>{@code +120} hit points, {@code +196} attack damage</li>
 *   <li>{@code +300} index into {@code db\dbButtons.dat} - the object's icon
 *       and its fixed cell in a building's command panel</li>
 *   <li>{@code +304} index into {@code db\dbgraphics.dat} - the first hop
 *       towards the object's actual mesh, see {@link DbGraphics}</li>
 *   <li>{@code +908} build-list length, {@code +1212} the build list itself:
 *       the object IDs (units) and tech IDs (upgrades) this object can
 *       produce. This is what a barracks' command panel is built from.</li>
 *   <li>{@code +912} the object's own ID - the value build lists and
 *       {@code db\dbtechtree.dat} cross-reference it by (<em>not</em> the
 *       record index)</li>
 * </ul>
 */
public final class DbObjects {

    private static final int RECORD_SIZE = 2012;
    private static final int OFF_HIT_POINTS = 120;
    private static final int OFF_ATTACK = 196;
    private static final int OFF_NAME_STRING = 296;
    private static final int OFF_BUTTON = 300;
    private static final int OFF_GRAPHICS = 304;
    private static final int OFF_BUILD_COUNT = 908;
    private static final int OFF_OBJECT_ID = 912;
    private static final int OFF_BUILD_LIST = 1212;

    /**
     * One object. {@code devName} is the developer-facing name baked into the
     * record ("A - b  Barracks (SP) (Greek)"); {@code nameStringId} is the ID
     * of the player-facing name in {@code Language2.dll} (see
     * {@code com.rnf.assets.StringTable}).
     */
    public record Entry(int recordIndex, int objectId, String devName, int nameStringId,
                        int buttonIndex, int graphicsIndex, int hitPoints, int attackDamage,
                        int[] buildList) {}

    private final List<Entry> entries;
    private final Map<Integer, Entry> byObjectId;

    private DbObjects(List<Entry> entries, Map<Integer, Entry> byObjectId) {
        this.entries = entries;
        this.byObjectId = byObjectId;
    }

    public static DbObjects parse(byte[] data) {
        DbTable table = new DbTable(data, RECORD_SIZE);
        List<Entry> entries = new ArrayList<>(table.recordCount);
        Map<Integer, Entry> byId = new HashMap<>();
        for (int i = 0; i < table.recordCount; i++) {
            int count = table.intAt(i, OFF_BUILD_COUNT);
            int[] buildList = new int[Math.max(0, Math.min(count, (RECORD_SIZE - OFF_BUILD_LIST) / 4))];
            for (int k = 0; k < buildList.length; k++) {
                buildList[k] = table.intAt(i, OFF_BUILD_LIST + 4 * k);
            }
            Entry e = new Entry(i,
                    table.intAt(i, OFF_OBJECT_ID),
                    table.longestAsciiRun(i, 4),
                    table.intAt(i, OFF_NAME_STRING),
                    table.intAt(i, OFF_BUTTON),
                    table.intAt(i, OFF_GRAPHICS),
                    table.intAt(i, OFF_HIT_POINTS),
                    table.intAt(i, OFF_ATTACK),
                    buildList);
            entries.add(e);
            byId.putIfAbsent(e.objectId(), e);
        }
        return new DbObjects(entries, byId);
    }

    public List<Entry> all() {
        return entries;
    }

    /** The object a build list entry / techtree entry refers to, or null. */
    public Entry byObjectId(int objectId) {
        return byObjectId.get(objectId);
    }

    /** First object whose developer name contains {@code needle} (case-insensitive), or null. */
    public Entry findByName(String needle) {
        String lower = needle.toLowerCase();
        for (Entry e : entries) {
            if (e.devName().toLowerCase().contains(lower)) return e;
        }
        return null;
    }
}
