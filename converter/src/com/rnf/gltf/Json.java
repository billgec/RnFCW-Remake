package com.rnf.gltf;

import java.util.List;
import java.util.Map;

/** Tiny JSON serializer for maps, lists, strings, numbers, booleans and primitive arrays. */
public final class Json {
    private Json() {}

    public static String write(Object o) {
        StringBuilder sb = new StringBuilder();
        append(sb, o, "", false);
        return sb.toString();
    }

    public static String pretty(Object o) {
        StringBuilder sb = new StringBuilder();
        append(sb, o, "", true);
        return sb.append('\n').toString();
    }

    private static void append(StringBuilder sb, Object o, String indent, boolean pretty) {
        String nl = pretty ? "\n" : "", inner = pretty ? indent + "  " : "";
        if (o == null) sb.append("null");
        else if (o instanceof String s) string(sb, s);
        else if (o instanceof Boolean || o instanceof Integer || o instanceof Long) sb.append(o);
        else if (o instanceof Number n) {
            double d = n.doubleValue();
            if (Double.isNaN(d) || Double.isInfinite(d)) d = 0;
            if (d == Math.rint(d) && Math.abs(d) < 1e15) sb.append((long) d);
            else sb.append((float) d == d ? Float.toString((float) d) : Double.toString(d));
        } else if (o instanceof Map<?, ?> m) {
            sb.append('{');
            boolean first = true;
            for (var e : m.entrySet()) {
                sb.append(first ? "" : ",").append(nl).append(inner);
                first = false;
                string(sb, String.valueOf(e.getKey()));
                sb.append(pretty ? ": " : ":");
                append(sb, e.getValue(), inner, pretty);
            }
            if (!m.isEmpty()) sb.append(nl).append(indent);
            sb.append('}');
        } else if (o instanceof List<?> l) {
            sb.append('[');
            for (int i = 0; i < l.size(); i++) {
                if (i > 0) sb.append(pretty ? ", " : ",");
                append(sb, l.get(i), inner, pretty);
            }
            sb.append(']');
        } else if (o instanceof float[] f) {
            sb.append('[');
            for (int i = 0; i < f.length; i++) { if (i > 0) sb.append(','); append(sb, f[i], inner, false); }
            sb.append(']');
        } else if (o instanceof int[] a) {
            sb.append('[');
            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(a[i]); }
            sb.append(']');
        } else string(sb, o.toString());
    }

    private static void string(StringBuilder sb, String s) {
        sb.append('"');
        for (char ch : s.toCharArray()) {
            switch (ch) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (ch < 0x20) sb.append(String.format("\\u%04x", (int) ch));
                    else sb.append(ch);
                }
            }
        }
        sb.append('"');
    }
}
