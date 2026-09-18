package com.rnf.db;

import com.rnf.assets.DataSsaArchive;
import com.rnf.assets.StringTable;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Gameplay values for a unit definition (.udf), read from its dbobjects record.
 *
 * <p>Verified fields (docs/FORMATS.md): +120 hit points, +196 damage, +296 name string.
 * Fields identified 2026-09-15 by comparing sword/spear/archer/cavalry/citizen/hero records
 * (StatsProbe) - plausible and type-consistent, but not yet confirmed in code:
 * <pre>
 *   +132 f32 attack range        (melee 0.6, cavalry 0.8, archer 8)
 *   +136 f32 line of sight       (8-10)
 *   +140 f32 attack interval, s  (sword 1.8, spear 2.1, archer 4.0, cavalry 1.0)
 *   +148 f32 movement speed      (archer/spear 0.8, sword 1.0, cavalry 1.4)
 *   +192 u32 attack type         (0 melee, 1 ranged, 2 cavalry, 5 citizen)
 *   +712/+716 f32 footprint      (infantry 0.45, cavalry 0.75 x 0.95)
 *   +560..+580 u32               probably class bonuses / armour (spear 24 vs cavalry)
 * </pre>
 * Distances are in game units; the models' UnitsPerMeter of 0.3281 means one unit is 3.048 m.
 */
public final class UnitStats {

    public static final double METERS_PER_UNIT = 1.0 / 0.3281;
    private static final Pattern SPECIAL = Pattern.compile(
            "Spawned|Defender|Cinematic|Campaign|Scenario|Test|flaming|Disabled|3rd Person|\\(SP\\)|Elite", Pattern.CASE_INSENSITIVE);

    private final byte[] raw;
    private final java.util.List<String> families;
    private final DbObjects objects;
    private final DbGraphics graphics;
    private final StringTable names;

    private UnitStats(byte[] raw, DbGraphics graphics, StringTable names, java.util.List<String> families) {
        this.families = families;
        this.raw = raw;
        this.objects = DbObjects.parse(raw);
        this.graphics = graphics;
        this.names = names;
    }

    public static UnitStats load(DataSsaArchive archive, Path language2Dll) throws IOException {
        StringTable names = Files.exists(language2Dll) ? StringTable.load(language2Dll) : null;
        byte[] familyTable = archive.readFile("db\\dbfamily.dat");
        java.util.List<String> families = new java.util.ArrayList<>();
        DbTable table = new DbTable(familyTable, 412);
        for (int i = 0; i < table.recordCount; i++) families.add(table.cString(i, 0, 100));
        return new UnitStats(archive.readFile("db\\dbobjects.dat"),
                DbGraphics.parse(archive.readFile("db\\dbgraphics.dat")), names, families);
    }

    /** The most "ordinary" record using this definition (not spawned/cinematic/campaign variants), or null. */
    public DbObjects.Entry recordFor(String udfName) {
        DbObjects.Entry best = null;
        int bestScore = Integer.MAX_VALUE;
        for (DbObjects.Entry e : objects.all()) {
            DbGraphics.Entry g = graphics.get(e.graphicsIndex());
            if (g == null || !udfName.equalsIgnoreCase(g.definitionName())) continue;
            int score = (SPECIAL.matcher(e.devName()).find() ? 1000 : 0) + e.devName().length();
            if (e.devName().contains("Level 1")) score -= 50;
            if (score < bestScore) {
                bestScore = score;
                best = e;
            }
        }
        return best;
    }

    public Map<String, Object> statsFor(String udfName) {
        DbObjects.Entry e = recordFor(udfName);
        return e == null ? null : statsFor(e);
    }

    public Map<String, Object> statsFor(DbObjects.Entry e) {
        ByteBuffer bb = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN);
        int base = 4 + e.recordIndex() * 2012;
        Map<String, Object> m = new LinkedHashMap<>();
        String name = names == null ? null : names.get(e.nameStringId());
        m.put("name", name != null && !name.isBlank() ? name : e.devName());
        m.put("dev_name", e.devName());
        m.put("record", e.recordIndex());
        m.put("line", line(e.devName()));
        m.put("hit_points", e.hitPoints());
        m.put("damage", e.attackDamage());
        m.put("attack_type", bb.getInt(base + 192));
        int family = bb.getInt(base + 104);
        m.put("family", family >= 0 && family < families.size() ? families.get(family) : String.valueOf(family));
        m.put("range_m", round(bb.getFloat(base + 132) * METERS_PER_UNIT));
        m.put("sight_m", round(bb.getFloat(base + 136) * METERS_PER_UNIT));
        m.put("attack_interval_s", round(bb.getFloat(base + 140)));
        m.put("speed_mps", round(bb.getFloat(base + 148) * METERS_PER_UNIT));
        m.put("footprint_m", List.of(round(bb.getFloat(base + 712) * METERS_PER_UNIT), round(bb.getFloat(base + 716) * METERS_PER_UNIT)));
        m.put("raw_560_580", List.of(bb.getInt(base + 560), bb.getInt(base + 564), bb.getInt(base + 568),
                bb.getInt(base + 572), bb.getInt(base + 580)));
        return m;
    }

    public String displayName(DbObjects.Entry e) {
        String name = names == null ? null : names.get(e.nameStringId());
        return name != null && !name.isBlank() ? name : e.devName();
    }

    /** Player-facing string from Language2.dll, or null. */
    public String stringById(int id) {
        return names == null ? null : names.get(id);
    }


    public DbObjects objects() {
        return objects;
    }

    public DbGraphics graphics() {
        return graphics;
    }

    /**
     * Identifies the upgrade line a unit belongs to: the developer name without its
     * category prefix and level marker, e.g. "A - Inf01 - Sword Infantry (Level 1 Greek)"
     * and its level 3 sibling both become "sword infantry (greek)".
     */
    public static String line(String devName) {
        return devName.replaceAll("^A - [A-Za-z]+[0-9]*[a-z]? - ", "")
                .replaceAll("\\(Level [0-9]+ ", "(")
                .replaceAll("\\(level [0-9]+ ", "(")
                .replaceAll("\\s+", " ").trim().toLowerCase();
    }


    private static double round(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
