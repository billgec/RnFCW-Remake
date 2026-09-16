package com.rnf.gr2;

/**
 * Granny 2 element type IDs, straight from opengr2's {@code typeinfo.h}
 * ({@code enum TypeIDs}) - "End of known elements as of Granny 2.12.0.2" per
 * that project's own comment.
 */
public final class TypeId {
    private TypeId() {}

    public static final int NONE = 0;
    public static final int INLINE = 1;
    public static final int REFERENCE = 2;
    public static final int REFERENCE_TO_ARRAY = 3;
    public static final int ARRAY_OF_REFERENCES = 4;
    public static final int VARIANT_REFERENCE = 5;
    public static final int REMOVED = 6;
    public static final int REFERENCE_TO_VARIANT_ARRAY = 7;
    public static final int STRING = 8;
    public static final int TRANSFORM = 9;
    public static final int REAL32 = 10;
    public static final int INT8 = 11;
    public static final int UINT8 = 12;
    public static final int BINORMAL_INT8 = 13;
    public static final int NORMAL_UINT8 = 14;
    public static final int INT16 = 15;
    public static final int UINT16 = 16;
    public static final int BINORMAL_INT16 = 17;
    public static final int NORMAL_UINT16 = 18;
    public static final int INT32 = 19;
    public static final int UINT32 = 20;
    public static final int REAL16 = 21;
    public static final int EMPTY_REFERENCE = 22;
    public static final int MAX = 23;

    public static boolean canHaveChildren(int type) {
        return type == REFERENCE_TO_ARRAY || type == INLINE || type == ARRAY_OF_REFERENCES
                || type == REFERENCE_TO_VARIANT_ARRAY || type == VARIANT_REFERENCE || type == REFERENCE;
    }

    /** True for the range Element_Parse recurses into (INLINE..REFERENCE_TO_VARIANT_ARRAY, excluding REMOVED). */
    public static boolean isContainer(int type) {
        return type >= INLINE && type <= REFERENCE_TO_VARIANT_ARRAY && type != REMOVED;
    }

    public static String name(int type) {
        return switch (type) {
            case NONE -> "NONE";
            case INLINE -> "INLINE";
            case REFERENCE -> "REFERENCE";
            case REFERENCE_TO_ARRAY -> "REFERENCE_TO_ARRAY";
            case ARRAY_OF_REFERENCES -> "ARRAY_OF_REFERENCES";
            case VARIANT_REFERENCE -> "VARIANT_REFERENCE";
            case REMOVED -> "REMOVED";
            case REFERENCE_TO_VARIANT_ARRAY -> "REFERENCE_TO_VARIANT_ARRAY";
            case STRING -> "STRING";
            case TRANSFORM -> "TRANSFORM";
            case REAL32 -> "REAL32";
            case INT8 -> "INT8";
            case UINT8 -> "UINT8";
            case BINORMAL_INT8 -> "BINORMAL_INT8";
            case NORMAL_UINT8 -> "NORMAL_UINT8";
            case INT16 -> "INT16";
            case UINT16 -> "UINT16";
            case BINORMAL_INT16 -> "BINORMAL_INT16";
            case NORMAL_UINT16 -> "NORMAL_UINT16";
            case INT32 -> "INT32";
            case UINT32 -> "UINT32";
            case REAL16 -> "REAL16";
            case EMPTY_REFERENCE -> "EMPTY_REFERENCE";
            default -> "UNKNOWN(" + type + ")";
        };
    }
}
