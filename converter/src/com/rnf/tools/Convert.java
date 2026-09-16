package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;
import com.rnf.assets.UnitDefinition;
import com.rnf.gltf.Gr2ToGltf;
import com.rnf.gltf.Json;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Asset pipeline entry point: pulls original assets out of data.ssa and writes open formats
 * into the Godot project.
 *
 * <pre>
 *   unit    &lt;data.ssa&gt; &lt;outRoot&gt; &lt;udfName&gt;...   units\NAME.udf -&gt; models/*.glb + textures/*.png + units/NAME.json
 *   texture &lt;data.ssa&gt; &lt;outRoot&gt; &lt;internal&gt;...  textures\x.dds|.sst -&gt; textures/x.png
 *   model   &lt;data.ssa&gt; &lt;outRoot&gt; &lt;internal&gt;...  models\x.gr2 -&gt; models/x.glb (no texture)
 * </pre>
 * {@code outRoot} is the Godot project's {@code assets/original} folder. File names are
 * lower-cased so the game can derive paths without caring about the original's casing.
 */
public final class Convert {

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("usage: unit|texture|model <data.ssa> <outRoot> <name>...");
            System.exit(1);
        }
        Path outRoot = Path.of(args[2]);
        Path dataSsa = Path.of(args[1]).toAbsolutePath();
        language2 = dataSsa.getParent().getParent().resolve("Language2.dll");
        int failures = 0;
        try (DataSsaArchive archive = new DataSsaArchive(args[1])) {
            for (int i = 3; i < args.length; i++) {
                try {
                    switch (args[0]) {
                        case "unit" -> unit(archive, outRoot, args[i]);
                        case "texture" -> texture(archive, outRoot, args[i]);
                        case "model" -> model(archive, outRoot, args[i], null);
                        default -> throw new IllegalArgumentException("unknown command " + args[0]);
                    }
                } catch (Exception e) {
                    failures++;
                    System.err.println("FAILED " + args[i] + ": " + e);
                }
            }
        }
        if (failures > 0) System.exit(2);
    }

    private static Path language2;
    private static com.rnf.db.DbButtons buttons;
    private static com.rnf.db.UnitStats stats;

    static void unit(DataSsaArchive archive, Path outRoot, String udfName) throws IOException {
        unit(archive, outRoot, udfName, null, Map.of());
    }

    static com.rnf.db.UnitStats stats(DataSsaArchive archive) throws IOException {
        if (stats == null) stats = com.rnf.db.UnitStats.load(archive, language2);
        return stats;
    }

    static void setLanguageDll(Path dll) {
        language2 = dll;
    }

    /**
     * @param record the dbobjects record to take gameplay values from (null: best guess by definition)
     * @param extra  additional manifest entries (icon, cost ...)
     */
    static void unit(DataSsaArchive archive, Path outRoot, String udfName, com.rnf.db.DbObjects.Entry record,
                     Map<String, Object> extra) throws IOException {
        stats(archive);
        udfName = udfName.toLowerCase();
        UnitDefinition def = UnitDefinition.load(archive, udfName);
        String texture = archive.contains(def.texturePath()) ? texture(archive, outRoot, def.texturePath()) : null;
        if (texture == null) System.err.println("warn: " + udfName + ": texture " + def.texturePath() + " missing");
        Map<String, byte[]> animations = new java.util.TreeMap<>();
        for (String ref : animationRefs(archive, udfName)) {
            animations.put(baseName(ref), archive.readFile(ref));
        }
        String name = baseName(def.modelPath()) + ".glb";
        List<String> warnings = Gr2ToGltf.convert(archive.readFile(def.modelPath()),
                texture == null ? null : "../textures/" + texture, animations, outRoot.resolve("models").resolve(name));
        for (String w : warnings) System.err.println("warn: " + udfName + ": " + w);
        String model = name;

        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("id", udfName.toLowerCase());
        manifest.put("model", "models/" + model);
        manifest.put("texture", texture == null ? null : "textures/" + texture);
        manifest.put("animations", new java.util.ArrayList<>(animations.keySet()));
        com.rnf.db.DbObjects.Entry statsRecord = record != null ? record : stats.recordFor(udfName);
        Map<String, Object> unitStats = statsRecord != null ? stats.statsFor(statsRecord) : null;
        if (!extra.containsKey("icon") && statsRecord != null) {
            if (buttons == null) buttons = com.rnf.db.DbButtons.parse(archive.readFile("db\\dbButtons.dat"));
            var button = buttons.get(statsRecord.buttonIndex());
            if (button != null && !button.iconPath().isEmpty()) {
                for (String candidate : List.of(button.iconPath() + ".dds", button.iconPath() + ".sst")) {
                    if (archive.contains(candidate)) {
                        manifest.put("icon", "textures/" + texture(archive, outRoot, candidate));
                        break;
                    }
                }
            }
        }
        if (unitStats == null) System.err.println("warn: " + udfName + ": no dbobjects record uses this definition");
        manifest.put("stats", unitStats);
        manifest.putAll(extra);
        manifest.put("source_model", def.modelPath());
        manifest.put("source_texture", def.texturePath());
        Path json = outRoot.resolve("units").resolve(udfName.toLowerCase() + ".json");
        Files.createDirectories(json.getParent());
        Files.writeString(json, Json.pretty(manifest));
        System.out.println("unit " + udfName + " -> " + model + ", " + texture);
    }

    static String model(DataSsaArchive archive, Path outRoot, String internal, String textureUri) throws IOException {
        String name = baseName(internal) + ".glb";
        List<String> warnings = Gr2ToGltf.convert(archive.readFile(internal), textureUri, outRoot.resolve("models").resolve(name));
        for (String w : warnings) System.err.println("warn: " + internal + ": " + w);
        return name;
    }

    static String texture(DataSsaArchive archive, Path outRoot, String internal) throws IOException {
        byte[] data = archive.readFile(internal);
        int dds = indexOfDdsMagic(data);
        if (dds < 0) throw new IOException(internal + ": no DDS payload");
        if (dds > 0) data = java.util.Arrays.copyOfRange(data, dds, data.length);
        BufferedImage img = DdsToPng.decode(data);
        String name = baseName(internal) + ".png";
        Path out = outRoot.resolve("textures").resolve(name);
        Files.createDirectories(out.getParent());
        ImageIO.write(img, "png", out.toFile());
        return name;
    }

    /** Animation files referenced by a unit definition ({@code "javelin\jav_walk_01"} style strings). */
    static java.util.Set<String> animationRefs(DataSsaArchive archive, String udfName) throws IOException {
        byte[] udf = archive.readFile("units\\" + udfName + ".udf");
        java.util.Set<String> refs = new java.util.TreeSet<>();
        int start = -1;
        for (int i = 0; i <= udf.length; i++) {
            boolean printable = i < udf.length && udf[i] >= 0x20 && udf[i] <= 0x7e;
            if (printable && start < 0) start = i;
            if (!printable && start >= 0) {
                String s = new String(udf, start, i - start, java.nio.charset.StandardCharsets.US_ASCII);
                start = -1;
                if (s.indexOf('\\') > 0 && !s.startsWith("models\\") && !s.startsWith("animations\\")) {
                    String candidate = "animations\\" + s.toLowerCase() + ".gr2";
                    if (archive.contains(candidate)) refs.add(candidate);
                }
            }
        }
        return refs;
    }

    private static int indexOfDdsMagic(byte[] d) {
        for (int i = 0; i + 4 <= Math.min(d.length, 64); i++) {
            if (d[i] == 'D' && d[i + 1] == 'D' && d[i + 2] == 'S' && d[i + 3] == ' ') return i;
        }
        return -1;
    }

    static String baseName(String internal) {
        String s = internal.substring(internal.lastIndexOf('\\') + 1).toLowerCase();
        int dot = s.lastIndexOf('.');
        return dot > 0 ? s.substring(0, dot) : s;
    }
}
