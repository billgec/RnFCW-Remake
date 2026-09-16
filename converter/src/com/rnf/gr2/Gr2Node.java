package com.rnf.gr2;

import java.util.ArrayList;
import java.util.List;

/**
 * One parsed field of a Granny 2 struct - the Java equivalent of opengr2's
 * {@code TElementGeneric} (and its type-specific subclasses), but unified
 * into a single class since Java doesn't need C's manual-allocation
 * per-type struct variants.
 *
 * <p>{@code type} is one of the {@link TypeId} constants. For container
 * types (INLINE, REFERENCE*, *ARRAY*) the actual data lives in
 * {@link #children} - one flat list of field-nodes, exactly mirroring the
 * C reference's behavior of appending every recursively-parsed field to the
 * same parent list regardless of array nesting (see
 * {@link Gr2ElementParser} for how repeated struct instances - i.e.
 * {@code arraySize > 1} - are laid out within that flat list). For leaf
 * (primitive) types, {@link #value} holds the decoded Java value.
 */
public final class Gr2Node {
    public final int type;
    public final String name;
    /** Element count: 1 for a scalar field, >1 for an inline fixed-size array, or the
     *  resolved row count for TYPEID_REFERENCETOARRAY/TYPEID_ARRAYOFREFERENCES. */
    public final int arraySize;
    /** Leaf value for primitive types: float[], int[], byte[], short[], or String. Null for containers. */
    public Object value;
    public final List<Gr2Node> children = new ArrayList<>();

    public Gr2Node(int type, String name, int arraySize) {
        this.type = type;
        this.name = name;
        this.arraySize = arraySize;
    }

    /** First direct child whose name equals {@code fieldName}, or null. */
    public Gr2Node get(String fieldName) {
        for (Gr2Node c : children) {
            if (fieldName.equals(c.name)) return c;
        }
        return null;
    }

    /** All direct children named {@code fieldName} (useful once you know how many fields a repeated row has). */
    public List<Gr2Node> getAll(String fieldName) {
        List<Gr2Node> out = new ArrayList<>();
        for (Gr2Node c : children) {
            if (fieldName.equals(c.name)) out.add(c);
        }
        return out;
    }

    @Override
    public String toString() {
        return "Gr2Node{" + TypeId.name(type) + " name=" + name + " arraySize=" + arraySize
                + (value != null ? " value=" + describeValue() : "") + " children=" + children.size() + "}";
    }

    private static final int INLINE_PREVIEW_MAX = 5;

    private String describeValue() {
        if (value instanceof float[] f) return "float" + preview(f.length, i -> String.valueOf(f[i]));
        if (value instanceof int[] i2) return "int" + preview(i2.length, i -> String.valueOf(i2[i]));
        if (value instanceof short[] s) return "short" + preview(s.length, i -> String.valueOf(s[i]));
        if (value instanceof byte[] b) return "byte" + preview(b.length, i -> String.valueOf(b[i] & 0xFF));
        return String.valueOf(value);
    }

    private static String preview(int length, java.util.function.IntFunction<String> at) {
        if (length <= INLINE_PREVIEW_MAX) {
            StringBuilder sb = new StringBuilder("[");
            for (int i = 0; i < length; i++) sb.append(i > 0 ? "," : "").append(at.apply(i));
            return sb.append(']').toString();
        }
        return "[" + length + "]";
    }

    /** Pretty-prints this node and its subtree, for exploring an unfamiliar .gr2's structure. */
    public void dump(StringBuilder sb, int depth) {
        sb.append("  ".repeat(depth)).append(this).append('\n');
        for (Gr2Node c : children) c.dump(sb, depth + 1);
    }
}
