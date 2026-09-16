package com.rnf.gr2;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Structured reader for a decompressed, fixed-up Granny2 buffer ({@link Gr2Container}).
 *
 * <p>Unlike {@link Gr2ElementParser}, which appends every field of every array row into
 * one flat child list, this keeps the real shape of the data:
 * <ul>
 *   <li>struct &rarr; {@code Map<String,Object>} (field order preserved)</li>
 *   <li>REFERENCE_TO_ARRAY / ARRAY_OF_REFERENCES / REFERENCE_TO_VARIANT_ARRAY &rarr;
 *       {@code List<Object>} of rows (a row of a single-field primitive struct such as
 *       {@code Indices16[] { UInt16 }} is still a one-entry map)</li>
 *   <li>REFERENCE / VARIANT_REFERENCE &rarr; the referenced struct, or null</li>
 *   <li>primitives &rarr; {@code float[]}, {@code int[]} or {@code String}; TRANSFORM &rarr;
 *       {@link Transform}</li>
 * </ul>
 * Referenced structs are memoised by (offset, type) so shared data (e.g. a mesh that is
 * listed under {@code Meshes} and again under {@code Models[].MeshBindings}) is parsed once
 * and yields the identical Java object - callers can use identity to resolve references.
 */
public final class Gr2Reader {

    /** Granny's granny_transform: flags, translation, orientation quaternion (x,y,z,w), 3x3 scale/shear (row-major). */
    public record Transform(int flags, float[] position, float[] orientation, float[] scaleShear) {}

    private static final int TYPE_ENTRY_SIZE = 32;
    private final Gr2Container c;
    private final Map<Long, Object> cache = new java.util.HashMap<>();

    public Gr2Reader(Gr2Container c) {
        this.c = c;
    }

    public static Map<String, Object> read(byte[] file) throws java.io.IOException {
        Gr2Container container = Gr2Container.parse(file);
        return new Gr2Reader(container).readRoot();
    }

    public Map<String, Object> readRoot() {
        return readStructAt(c.typeOffset, c.rootOffset);
    }

    private Map<String, Object> readStructAt(int typeOffset, int dataOffset) {
        long key = ((long) dataOffset << 32) | (typeOffset & 0xFFFFFFFFL);
        Object cached = cache.get(key);
        if (cached != null) {
            @SuppressWarnings("unchecked") Map<String, Object> m = (Map<String, Object>) cached;
            return m;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        cache.put(key, out);
        readFields(typeOffset, new int[]{dataOffset}, out);
        return out;
    }

    /** Size in bytes of one instance of the struct described by {@code typeOffset}. */
    private int structSize(int typeOffset) {
        int size = 0;
        for (int t = typeOffset; ; t += TYPE_ENTRY_SIZE) {
            int type = c.readU32At(t);
            if (type == TypeId.NONE || type >= TypeId.MAX) break;
            int arraySize = Math.max(1, c.readU32At(t + 12));
            int children = c.readU32At(t + 8);
            size += arraySize * switch (type) {
                case TypeId.INLINE -> structSize(children);
                case TypeId.REFERENCE, TypeId.EMPTY_REFERENCE, TypeId.STRING -> 4;
                case TypeId.REFERENCE_TO_ARRAY, TypeId.ARRAY_OF_REFERENCES, TypeId.VARIANT_REFERENCE -> 8;
                case TypeId.REFERENCE_TO_VARIANT_ARRAY -> 12;
                case TypeId.TRANSFORM -> 68;
                case TypeId.REAL32, TypeId.INT32, TypeId.UINT32 -> 4;
                case TypeId.INT16, TypeId.UINT16, TypeId.BINORMAL_INT16, TypeId.NORMAL_UINT16, TypeId.REAL16 -> 2;
                case TypeId.INT8, TypeId.UINT8, TypeId.BINORMAL_INT8, TypeId.NORMAL_UINT8 -> 1;
                default -> 0;
            };
        }
        return size;
    }

    private void readFields(int typeOffset, int[] cursor, Map<String, Object> out) {
        for (int t = typeOffset; ; t += TYPE_ENTRY_SIZE) {
            int type = c.readU32At(t);
            if (type == TypeId.NONE || type >= TypeId.MAX) break;
            int nameOffset = c.readU32At(t + 4);
            int children = c.readU32At(t + 8);
            int arraySize = Math.max(1, c.readU32At(t + 12));
            String name = nameOffset != 0 ? c.readStringAt(nameOffset) : "?";
            out.put(name, readValue(type, children, arraySize, cursor));
        }
    }

    private Object readValue(int type, int children, int arraySize, int[] cur) {
        int p = cur[0];
        switch (type) {
            case TypeId.INLINE -> {
                if (arraySize == 1) {
                    Map<String, Object> m = new LinkedHashMap<>();
                    readFields(children, cur, m);
                    return m;
                }
                List<Object> rows = new ArrayList<>();
                for (int i = 0; i < arraySize; i++) {
                    Map<String, Object> m = new LinkedHashMap<>();
                    readFields(children, cur, m);
                    rows.add(m);
                }
                return rows;
            }
            case TypeId.REFERENCE, TypeId.EMPTY_REFERENCE -> {
                int ref = c.readU32At(p);
                cur[0] = p + 4;
                return (ref == 0 || children == 0) ? null : readStructAt(children, ref);
            }
            case TypeId.VARIANT_REFERENCE -> {
                int variantType = c.readU32At(p);
                int ref = c.readU32At(p + 4);
                cur[0] = p + 8;
                return (ref == 0 || variantType == 0) ? null : readStructAt(variantType, ref);
            }
            case TypeId.REFERENCE_TO_ARRAY -> {
                int count = c.readU32At(p);
                int base = c.readU32At(p + 4);
                cur[0] = p + 8;
                return readRows(children, count, base);
            }
            case TypeId.REFERENCE_TO_VARIANT_ARRAY -> {
                int variantType = c.readU32At(p);
                int count = c.readU32At(p + 4);
                int base = c.readU32At(p + 8);
                cur[0] = p + 12;
                return readRows(variantType, count, base);
            }
            case TypeId.ARRAY_OF_REFERENCES -> {
                int count = c.readU32At(p);
                int table = c.readU32At(p + 4);
                cur[0] = p + 8;
                List<Object> rows = new ArrayList<>(count);
                for (int i = 0; i < count && table != 0; i++) {
                    int ref = c.readU32At(table + i * 4);
                    rows.add(ref == 0 || children == 0 ? null : readStructAt(children, ref));
                }
                return rows;
            }
            case TypeId.STRING -> {
                int s = c.readU32At(p);
                cur[0] = p + 4;
                return s == 0 ? null : c.readStringAt(s);
            }
            case TypeId.TRANSFORM -> {
                if (arraySize != 1) throw new IllegalStateException("TRANSFORM arrays not supported");
                int flags = c.readU32At(p);
                float[] pos = floats(p + 4, 3), rot = floats(p + 16, 4), ss = floats(p + 32, 9);
                cur[0] = p + 68;
                return new Transform(flags, pos, rot, ss);
            }
            case TypeId.REAL32 -> {
                cur[0] = p + 4 * arraySize;
                return floats(p, arraySize);
            }
            case TypeId.INT32, TypeId.UINT32 -> {
                int[] v = new int[arraySize];
                for (int i = 0; i < arraySize; i++) v[i] = c.readU32At(p + 4 * i);
                cur[0] = p + 4 * arraySize;
                return v;
            }
            case TypeId.INT16, TypeId.BINORMAL_INT16 -> {
                int[] v = new int[arraySize];
                for (int i = 0; i < arraySize; i++) v[i] = c.readU16At(p + 2 * i);
                cur[0] = p + 2 * arraySize;
                return v;
            }
            case TypeId.UINT16, TypeId.NORMAL_UINT16, TypeId.REAL16 -> {
                int[] v = new int[arraySize];
                for (int i = 0; i < arraySize; i++) v[i] = c.readU16At(p + 2 * i) & 0xFFFF;
                cur[0] = p + 2 * arraySize;
                return v;
            }
            case TypeId.INT8, TypeId.BINORMAL_INT8 -> {
                int[] v = new int[arraySize];
                for (int i = 0; i < arraySize; i++) v[i] = c.readU8At(p + i);
                cur[0] = p + arraySize;
                return v;
            }
            case TypeId.UINT8, TypeId.NORMAL_UINT8 -> {
                int[] v = new int[arraySize];
                for (int i = 0; i < arraySize; i++) v[i] = c.readU8At(p + i) & 0xFF;
                cur[0] = p + arraySize;
                return v;
            }
            default -> {
                return null;
            }
        }
    }

    private List<Object> readRows(int rowType, int count, int base) {
        List<Object> rows = new ArrayList<>(Math.max(count, 0));
        if (count <= 0 || base == 0 || rowType == 0) return rows;
        int size = structSize(rowType);
        for (int i = 0; i < count; i++) {
            Map<String, Object> m = new LinkedHashMap<>();
            readFields(rowType, new int[]{base + i * size}, m);
            rows.add(m);
        }
        return rows;
    }

    private float[] floats(int p, int n) {
        float[] v = new float[n];
        for (int i = 0; i < n; i++) v[i] = c.readFloatAt(p + 4 * i);
        return v;
    }

    // --- small typed accessors for callers ---

    @SuppressWarnings("unchecked")
    public static Map<String, Object> map(Object o) { return (Map<String, Object>) o; }

    @SuppressWarnings("unchecked")
    public static List<Object> list(Object o) { return o == null ? List.of() : (List<Object>) o; }

    /** Prints the structure (field names, list sizes, first row of each list) for exploration. */
    public static void dump(Object o, String indent, StringBuilder sb, int depth, java.util.IdentityHashMap<Object, Boolean> seen) {
        if (depth > 12) { sb.append(indent).append("...\n"); return; }
        if (o instanceof Map<?, ?> m) {
            if (seen.put(o, true) != null) { sb.append(indent).append("(shared ref)\n"); return; }
            for (var e : m.entrySet()) {
                Object v = e.getValue();
                if (v instanceof Map || v instanceof List) {
                    sb.append(indent).append(e.getKey()).append(v instanceof List<?> l ? " [" + l.size() + "]" : " {}").append('\n');
                    dump(v, indent + "  ", sb, depth + 1, seen);
                } else {
                    sb.append(indent).append(e.getKey()).append(" = ").append(brief(v)).append('\n');
                }
            }
        } else if (o instanceof List<?> l && !l.isEmpty()) {
            dump(l.get(0), indent + "#0 ", sb, depth + 1, seen);
        }
    }

    private static String brief(Object v) {
        if (v instanceof float[] f) return f.length <= 16 ? java.util.Arrays.toString(f) : "float[" + f.length + "]";
        if (v instanceof int[] i) return i.length <= 16 ? java.util.Arrays.toString(i) : "int[" + i.length + "]";
        if (v instanceof Transform t) return "T(flags=" + t.flags() + " pos=" + java.util.Arrays.toString(t.position())
                + " rot=" + java.util.Arrays.toString(t.orientation()) + ")";
        return String.valueOf(v);
    }

    public static void main(String[] args) throws Exception {
        Map<String, Object> root = read(java.nio.file.Files.readAllBytes(java.nio.file.Path.of(args[0])));
        StringBuilder sb = new StringBuilder();
        dump(root, "", sb, 0, new java.util.IdentityHashMap<>());
        System.out.print(sb);
    }
}
