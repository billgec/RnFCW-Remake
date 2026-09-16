package com.rnf.gr2;

/**
 * Java port of opengr2's generic node walker ({@code typeinfo.c}'s
 * {@code TypeInfo_Parse} + {@code elements_parse.c}'s {@code Element_Parse}
 * / {@code Element_ParsePrimitive} / {@code Element_ParseNode}) - the piece
 * that turns a self-describing type-descriptor chain plus a raw data blob
 * into a real, navigable tree ({@link Gr2Node}).
 *
 * <p>All references in {@link Gr2Container}'s output are already resolved
 * to plain absolute offsets into its flat buffer (see that class's
 * javadoc), so this class never needs the C library's "virtual pointer"
 * indirection - a resolved reference field's value here is just the offset
 * to jump to (0 = null).
 */
public final class Gr2ElementParser {

    private final Gr2Container c;

    public Gr2ElementParser(Gr2Container c) {
        this.c = c;
    }

    /** Parses the file's root struct instance (fileInfo.root, described by fileInfo.type). */
    public Gr2Node parseRoot() {
        Gr2Node root = new Gr2Node(TypeId.INLINE, "<root>", 1);
        int[] dataCursor = {c.rootOffset};
        parseStructFields(c.typeOffset, c.rootOffset, dataCursor, root);
        return root;
    }

    /**
     * One {@code TNodeTypeInfo} entry (32 bytes, 32-bit mode):
     * type(u32) nameOffset(u32) childrenOffset(u32) arraySize(i32) extra[12] extra4(u32).
     */
    private record TypeEntry(int type, String name, int childrenOffset, int arraySize) {}

    private TypeEntry readTypeEntry(int typeOffset) {
        int type = c.readU32At(typeOffset);
        if (type == TypeId.NONE || type >= TypeId.MAX) return null;
        int nameOffset = c.readU32At(typeOffset + 4);
        int childrenOffset = c.readU32At(typeOffset + 8);
        int arraySize = c.readU32At(typeOffset + 12);
        String name = nameOffset != 0 ? c.readStringAt(nameOffset) : null;
        return new TypeEntry(type, name, childrenOffset, arraySize);
    }

    private static final int TYPE_ENTRY_SIZE = 32; // 32-bit mode: 4+4+4+4+12+4

    /**
     * Walks one struct's field schema (the type-descriptor chain starting at
     * {@code typeOffset}) against its data (via the shared, threaded
     * {@code dataCursor}), appending every parsed field to {@code parent}.
     * Mirrors {@code Element_Parse} - see its javadoc-equivalent comment in
     * the C source for why the cursor is shared across repeated rows.
     */
    private void parseStructFields(int typeOffset, int dataBase, int[] dataCursor, Gr2Node parent) {
        int typePos = typeOffset;
        while (true) {
            TypeEntry te = readTypeEntry(typePos);
            if (te == null) break;
            typePos += TYPE_ENTRY_SIZE;

            int arraySize = te.arraySize() != 0 ? te.arraySize() : 1;
            Gr2Node node = new Gr2Node(te.type(), te.name(), arraySize);
            parsePrimitive(node, dataCursor);
            if (TypeId.isContainer(te.type())) {
                parseNode(node, te, dataBase, dataCursor);
            }
            parent.children.add(node);
        }
    }

    /** Reads a leaf value / reference pointer at the current cursor, advancing it. Mirrors Element_ParsePrimitive. */
    private void parsePrimitive(Gr2Node node, int[] cursor) {
        int pos = cursor[0];
        switch (node.type) {
            case TypeId.NONE, TypeId.INLINE -> { /* no data at this level */ }

            case TypeId.INT8, TypeId.BINORMAL_INT8 -> {
                byte[] v = new byte[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readU8At(pos + i);
                node.value = v;
                pos += node.arraySize;
            }
            case TypeId.UINT8, TypeId.NORMAL_UINT8 -> {
                int[] v = new int[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readU8At(pos + i) & 0xFF;
                node.value = v;
                pos += node.arraySize;
            }
            case TypeId.INT16, TypeId.BINORMAL_INT16 -> {
                short[] v = new short[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readU16At(pos + i * 2);
                node.value = v;
                pos += node.arraySize * 2;
            }
            case TypeId.UINT16, TypeId.NORMAL_UINT16, TypeId.REAL16 -> {
                int[] v = new int[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readU16At(pos + i * 2) & 0xFFFF;
                node.value = v;
                pos += node.arraySize * 2;
            }
            case TypeId.INT32, TypeId.UINT32 -> {
                int[] v = new int[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readU32At(pos + i * 4);
                node.value = v;
                pos += node.arraySize * 4;
            }
            case TypeId.REAL32 -> {
                float[] v = new float[node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readFloatAt(pos + i * 4);
                node.value = v;
                pos += node.arraySize * 4;
            }
            case TypeId.TRANSFORM -> {
                // TTransformation = 68 bytes: flags(4) + translation(12) + rotation(16) + scaleShear(36).
                // Not needed for static mesh geometry - stored as raw floats [flags-as-float, tx,ty,tz, rx,ry,rz,rw, 3x3 scale/shear]
                // in case a future skeleton/animation pass wants it; kept simple deliberately.
                float[] v = new float[17 * node.arraySize];
                for (int i = 0; i < v.length; i++) v[i] = c.readFloatAt(pos + i * 4);
                node.value = v;
                pos += 68 * node.arraySize;
            }

            case TypeId.REFERENCE, TypeId.EMPTY_REFERENCE -> {
                node.value = c.readU32At(pos); // resolved absolute offset, 0 = null
                pos += 4;
            }
            case TypeId.STRING -> {
                int strOffset = c.readU32At(pos);
                node.value = strOffset != 0 ? c.readStringAt(strOffset) : null;
                pos += 4;
            }
            case TypeId.REFERENCE_TO_ARRAY -> {
                int count = c.readU32At(pos);
                pos += 4;
                int dataPtr = c.readU32At(pos);
                pos += 4;
                node.value = new int[]{count, dataPtr}; // [rowCount, rowsBaseOffset]
            }
            case TypeId.REFERENCE_TO_VARIANT_ARRAY -> {
                int variantOffset = c.readU32At(pos);
                pos += 4;
                int count = c.readU32At(pos);
                pos += 4;
                int dataPtr = c.readU32At(pos);
                pos += 4;
                node.value = new int[]{count, dataPtr, variantOffset};
            }
            case TypeId.VARIANT_REFERENCE -> {
                int variantOffset = c.readU32At(pos);
                pos += 4;
                int dataPtr = c.readU32At(pos);
                pos += 4;
                node.value = new int[]{dataPtr, variantOffset};
            }
            case TypeId.ARRAY_OF_REFERENCES -> {
                int count = c.readU32At(pos);
                pos += 4;
                int tableOffset = c.readU32At(pos);
                pos += 4;
                int[] refs = new int[count];
                for (int i = 0; i < count; i++) refs[i] = c.readU32At(tableOffset + i * 4);
                node.value = refs; // each entry is a resolved absolute offset (or 0)
            }
            default -> { /* unknown type: leave unread, matches C's dbg_printf-and-continue */ }
        }
        cursor[0] = pos;
    }

    /**
     * Recurses into a container field's children. Mirrors Element_ParseNode,
     * with one addition opengr2 doesn't do: for the two genuinely "variant"
     * types (VARIANT_REFERENCE, REFERENCE_TO_VARIANT_ARRAY), their static
     * {@code childrenOffset} in the schema is 0 - the field's row type isn't
     * known at compile time (e.g. different meshes can have different
     * vertex layouts). Its type-descriptor chain lives at a DATA-provided
     * offset instead - the third value read in {@link #parsePrimitive} -
     * confirmed empirically against a real vertex array (childrenOffset=0,
     * that third value pointing at a valid nested TNodeTypeInfo chain that
     * decodes into exactly the fields you'd expect: Position/Normal/UVs).
     */
    private void parseNode(Gr2Node node, TypeEntry te, int outerDataBase, int[] outerCursor) {
        switch (node.type) {
            case TypeId.REFERENCE, TypeId.EMPTY_REFERENCE -> {
                if (te.childrenOffset() == 0) return;
                int refOffset = (int) node.value;
                if (refOffset == 0) return;
                int[] cursor = {refOffset};
                parseStructFields(te.childrenOffset(), refOffset, cursor, node);
            }

            case TypeId.VARIANT_REFERENCE -> {
                int[] v = (int[]) node.value; // [dataPtr, variantTypeOffset]
                int refOffset = v[0];
                int variantType = v[1];
                if (refOffset == 0 || variantType == 0) return;
                int[] cursor = {refOffset};
                parseStructFields(variantType, refOffset, cursor, node);
            }

            case TypeId.REFERENCE_TO_ARRAY -> {
                if (te.childrenOffset() == 0) return;
                int[] v = (int[]) node.value; // [count, dataPtr]
                int count = v[0], rowsBase = v[1];
                if (rowsBase == 0 || count == 0) return;
                int[] cursor = {rowsBase}; // threaded across all rows, see class javadoc
                for (int i = 0; i < count; i++) {
                    parseStructFields(te.childrenOffset(), rowsBase, cursor, node);
                }
            }

            case TypeId.REFERENCE_TO_VARIANT_ARRAY -> {
                int[] v = (int[]) node.value; // [count, dataPtr, variantTypeOffset]
                int count = v[0], rowsBase = v[1], variantType = v[2];
                if (rowsBase == 0 || count == 0 || variantType == 0) return;
                int[] cursor = {rowsBase};
                for (int i = 0; i < count; i++) {
                    parseStructFields(variantType, rowsBase, cursor, node);
                }
            }

            case TypeId.ARRAY_OF_REFERENCES -> {
                if (te.childrenOffset() == 0) return;
                int[] refs = (int[]) node.value;
                for (int ref : refs) {
                    if (ref == 0) continue;
                    int[] cursor = {ref}; // fresh cursor per element - independent allocations
                    parseStructFields(te.childrenOffset(), ref, cursor, node);
                }
            }

            case TypeId.INLINE -> {
                if (te.childrenOffset() == 0) return;
                parseStructFields(te.childrenOffset(), outerDataBase, outerCursor, node);
            }

            default -> { /* not a container type */ }
        }
    }
}
