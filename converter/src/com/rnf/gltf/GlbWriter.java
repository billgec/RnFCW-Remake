package com.rnf.gltf;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Minimal glTF 2.0 binary (.glb) builder: a JSON document assembled from plain maps/lists
 * plus one shared binary buffer. Only what the converter needs - no validation beyond
 * what the spec requires for loaders (accessor min/max on POSITION, 4-byte alignment).
 */
public final class GlbWriter {

    public static final int FLOAT = 5126, UNSIGNED_BYTE = 5121, UNSIGNED_SHORT = 5123, UNSIGNED_INT = 5125;
    private static final int ARRAY_BUFFER = 34962, ELEMENT_ARRAY_BUFFER = 34963;

    public final Map<String, Object> json = new LinkedHashMap<>();
    private final ByteArrayOutputStream bin = new ByteArrayOutputStream();

    public GlbWriter() {
        json.put("asset", Map.of("version", "2.0", "generator", "rnf-converter"));
    }

    @SuppressWarnings("unchecked")
    public List<Object> array(String key) {
        return (List<Object>) json.computeIfAbsent(key, k -> new ArrayList<>());
    }

    /** Appends {@code obj} to the top-level array {@code key} and returns its index. */
    public int add(String key, Object obj) {
        List<Object> a = array(key);
        a.add(obj);
        return a.size() - 1;
    }

    private int bufferView(byte[] data, Integer target) {
        while (bin.size() % 4 != 0) bin.write(0);
        Map<String, Object> view = new LinkedHashMap<>();
        view.put("buffer", 0);
        view.put("byteOffset", bin.size());
        view.put("byteLength", data.length);
        if (target != null) view.put("target", target);
        bin.writeBytes(data);
        return add("bufferViews", view);
    }

    public int floatAccessor(float[] values, int components, String type, boolean withBounds, Integer target) {
        ByteBuffer bb = ByteBuffer.allocate(values.length * 4).order(ByteOrder.LITTLE_ENDIAN);
        for (float v : values) bb.putFloat(v);
        Map<String, Object> acc = new LinkedHashMap<>();
        acc.put("bufferView", bufferView(bb.array(), target));
        acc.put("componentType", FLOAT);
        acc.put("count", values.length / components);
        acc.put("type", type);
        if (withBounds) {
            double[] min = new double[components], max = new double[components];
            java.util.Arrays.fill(min, Double.MAX_VALUE);
            java.util.Arrays.fill(max, -Double.MAX_VALUE);
            for (int i = 0; i < values.length; i++) {
                int c = i % components;
                min[c] = Math.min(min[c], values[i]);
                max[c] = Math.max(max[c], values[i]);
            }
            acc.put("min", toList(min));
            acc.put("max", toList(max));
        }
        return add("accessors", acc);
    }

    public int byteAccessor(int[] values, int components, String type, boolean normalized) {
        byte[] data = new byte[values.length];
        for (int i = 0; i < values.length; i++) data[i] = (byte) values[i];
        Map<String, Object> acc = new LinkedHashMap<>();
        acc.put("bufferView", bufferView(data, ARRAY_BUFFER));
        acc.put("componentType", UNSIGNED_BYTE);
        if (normalized) acc.put("normalized", true);
        acc.put("count", values.length / components);
        acc.put("type", type);
        return add("accessors", acc);
    }

    public int indexAccessor(int[] indices) {
        ByteBuffer bb = ByteBuffer.allocate(indices.length * 4).order(ByteOrder.LITTLE_ENDIAN);
        for (int i : indices) bb.putInt(i);
        Map<String, Object> acc = new LinkedHashMap<>();
        acc.put("bufferView", bufferView(bb.array(), ELEMENT_ARRAY_BUFFER));
        acc.put("componentType", UNSIGNED_INT);
        acc.put("count", indices.length);
        acc.put("type", "SCALAR");
        return add("accessors", acc);
    }

    private static List<Object> toList(double[] d) {
        List<Object> l = new ArrayList<>();
        for (double v : d) l.add(v);
        return l;
    }

    public void write(Path out) throws IOException {
        if (bin.size() > 0) json.put("buffers", List.of(Map.of("byteLength", bin.size())));
        byte[] jsonBytes = Json.write(json).getBytes(StandardCharsets.UTF_8);
        int jsonPad = (4 - jsonBytes.length % 4) % 4;
        while (bin.size() % 4 != 0) bin.write(0);
        byte[] binBytes = bin.toByteArray();
        int total = 12 + 8 + jsonBytes.length + jsonPad + (binBytes.length > 0 ? 8 + binBytes.length : 0);
        ByteBuffer bb = ByteBuffer.allocate(total).order(ByteOrder.LITTLE_ENDIAN);
        bb.putInt(0x46546C67).putInt(2).putInt(total);
        bb.putInt(jsonBytes.length + jsonPad).putInt(0x4E4F534A).put(jsonBytes);
        for (int i = 0; i < jsonPad; i++) bb.put((byte) ' ');
        if (binBytes.length > 0) bb.putInt(binBytes.length).putInt(0x004E4942).put(binBytes);
        Files.createDirectories(out.toAbsolutePath().getParent());
        Files.write(out, bb.array());
    }
}
