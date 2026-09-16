package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;
import com.rnf.db.DbGraphics;
import com.rnf.db.DbObjects;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/**
 * Reverse-engineering helper: prints every 4-byte field of several dbobjects records side by
 * side (as int and as float) so fields whose values follow the unit type - speed, range,
 * attack rate, sight - stand out. Records are chosen by developer-name substring.
 *
 * <pre>StatsProbe &lt;data.ssa&gt; "Sword Infantry (Level 1 Greek)" "Archer (Level 1 Greek)" ...</pre>
 */
public final class StatsProbe {
    public static void main(String[] args) throws Exception {
        try (DataSsaArchive archive = new DataSsaArchive(args[0])) {
            byte[] raw = archive.readFile("db\\dbobjects.dat");
            DbObjects objects = DbObjects.parse(raw);
            DbGraphics graphics = DbGraphics.parse(archive.readFile("db\\dbgraphics.dat"));
            List<DbObjects.Entry> picked = new ArrayList<>();
            for (int i = 1; i < args.length; i++) {
                DbObjects.Entry e = args[i].startsWith("#") ? objects.all().get(Integer.parseInt(args[i].substring(1))) : objects.findByName(args[i]);
                if (e == null) { System.err.println("not found: " + args[i]); continue; }
                DbGraphics.Entry g = graphics.get(e.graphicsIndex());
                System.out.printf("#%d %s  hp=%d dmg=%d udf=%s%n", picked.size(), e.devName(), e.hitPoints(),
                        e.attackDamage(), g == null ? "?" : g.definitionName());
                picked.add(e);
            }
            ByteBuffer bb = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN);
            for (int off = 0; off < 2012; off += 4) {
                StringBuilder ints = new StringBuilder(), floats = new StringBuilder();
                boolean varies = false, plausibleFloat = true;
                int first = 0;
                for (int k = 0; k < picked.size(); k++) {
                    int pos = 4 + picked.get(k).recordIndex() * 2012 + off;
                    int v = bb.getInt(pos);
                    float f = bb.getFloat(pos);
                    if (k == 0) first = v; else if (v != first) varies = true;
                    ints.append(String.format("%12d", v));
                    floats.append(String.format("%12.3f", f));
                    if (!(f == 0 || (Math.abs(f) > 1e-3 && Math.abs(f) < 1e5))) plausibleFloat = false;
                }
                if (!varies) continue;
                System.out.printf("+%-5d int %s%n", off, ints);
                if (plausibleFloat) System.out.printf("       flt %s%n", floats);
            }
        }
    }
}
