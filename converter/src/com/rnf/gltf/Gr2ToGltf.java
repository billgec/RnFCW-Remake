package com.rnf.gltf;

import com.rnf.gr2.Gr2Reader;
import com.rnf.gr2.Gr2Reader.Transform;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static com.rnf.gr2.Gr2Reader.list;
import static com.rnf.gr2.Gr2Reader.map;

/**
 * Converts a Granny2 model file into a skinned glTF 2.0 binary.
 *
 * <p>Geometry, bone transforms and inverse bind matrices are copied unchanged (Granny's
 * row-major InverseWorld4x4 has the same flat layout as glTF's column-major matrices).
 * The file's axis system (3ds Max: Z up, feet-ish units) is handled by a single root node
 * {@code rnf_root} that rotates -90 deg about X and scales by {@code 1/UnitsPerMeter}, so
 * everything below it stays in authored space and animations exported the same way line up.
 *
 * <p>Helper models named {@code -tag xyz} (hp bar anchor, projectile spawn, weapon mount,
 * impact points ...) become empty nodes named {@code tag_xyz}.
 */
public final class Gr2ToGltf {

    private static final float[] Z_UP_TO_Y_UP = {-0.70710678f, 0f, 0f, 0.70710678f};

    private final GlbWriter g = new GlbWriter();
    private final String textureUri;
    private final List<String> warnings = new ArrayList<>();

    private Gr2ToGltf(String textureUri) {
        this.textureUri = textureUri;
    }

    /** @param textureUri relative URI of the skin texture to reference from every material, or null */
    public static List<String> convert(byte[] gr2, String textureUri, Path out) throws IOException {
        return convert(gr2, textureUri, Map.of(), out);
    }

    /**
     * @param animations animation name -&gt; raw animation .gr2; tracks are matched to bone
     *                   nodes by name, so the animations must target this model's skeleton
     */
    public static List<String> convert(byte[] gr2, String textureUri, Map<String, byte[]> animations, Path out) throws IOException {
        Gr2ToGltf c = new Gr2ToGltf(textureUri);
        c.build(Gr2Reader.read(gr2));
        for (var e : animations.entrySet()) c.addAnimation(e.getKey(), Gr2Reader.read(e.getValue()));
        c.g.write(out);
        return c.warnings;
    }

    private final Map<String, Integer> nodeByName = new HashMap<>();

    private void addAnimation(String name, Map<String, Object> file) {
        List<Object> samplers = new ArrayList<>();
        List<Object> channels = new ArrayList<>();
        int unmatched = 0;
        for (Object tgo : list(file.get("TrackGroups"))) {
            for (Object tto : list(map(tgo).get("TransformTracks"))) {
                Map<String, Object> track = map(tto);
                String trackName = String.valueOf(track.get("Name"));
                Integer node = nodeByName.get(trackName.startsWith("-tag ") ? "tag_" + trackName.substring(5) : trackName);
                if (node == null) {
                    unmatched++;
                    continue;
                }
                addChannel(samplers, channels, node, "translation", map(track.get("PositionCurve")), 3);
                addChannel(samplers, channels, node, "rotation", map(track.get("OrientationCurve")), 4);
                addChannel(samplers, channels, node, "scale", map(track.get("ScaleShearCurve")), 9);
            }
        }
        if (unmatched > 0) warnings.add("animation " + name + ": " + unmatched + " tracks without matching node");
        if (channels.isEmpty()) {
            warnings.add("animation " + name + ": no usable channels");
            return;
        }
        Map<String, Object> anim = new LinkedHashMap<>();
        anim.put("name", name);
        anim.put("samplers", samplers);
        anim.put("channels", channels);
        g.add("animations", anim);
    }

    /**
     * Granny 2.4/2.5 curves here are uncompressed B-splines (Degree, Knots[], Controls[]).
     * Knots are times in seconds with one control per knot; degree 0 is a step/constant curve.
     * Degree-2 curves are emitted as linear keys at the knots - with knots every ~2 frames the
     * control points sit practically on the curve (same approach as other Granny exporters).
     */
    private void addChannel(List<Object> samplers, List<Object> channels, int node, String path,
                            Map<String, Object> curve, int dim) {
        if (curve == null) return;
        float[] knots = flatten(list(curve.get("Knots")));
        float[] controls = flatten(list(curve.get("Controls")));
        if (controls.length == 0) return;
        int count = controls.length / dim;
        if (knots.length != count) {
            if (count == 1) knots = new float[]{0f};
            else {
                warnings.add("curve with " + knots.length + " knots but " + count + " controls on node " + node);
                return;
            }
        }
        int outDim = dim == 9 ? 3 : dim;
        float[] values = new float[count * outDim];
        for (int i = 0; i < count; i++) {
            int s = i * dim, d = i * outDim;
            if (dim == 9) {
                values[d] = controls[s];
                values[d + 1] = controls[s + 4];
                values[d + 2] = controls[s + 8];
            } else {
                System.arraycopy(controls, s, values, d, dim);
            }
            if (dim == 4) {
                double len = Math.sqrt(values[d] * values[d] + values[d + 1] * values[d + 1] + values[d + 2] * values[d + 2] + values[d + 3] * values[d + 3]);
                if (len < 1e-8) { values[d + 3] = 1; len = 1; }
                boolean flip = i > 0 && values[d] * values[d - 4] + values[d + 1] * values[d - 3] + values[d + 2] * values[d - 2] + values[d + 3] * values[d - 1] < 0;
                for (int k = 0; k < 4; k++) values[d + k] = (float) (values[d + k] / len * (flip ? -1 : 1));
            }
        }
        int degree = curve.get("Degree") instanceof int[] dg ? dg[0] : 0;
        Map<String, Object> sampler = new LinkedHashMap<>();
        sampler.put("input", g.floatAccessor(knots, 1, "SCALAR", true, null));
        sampler.put("interpolation", degree == 0 && count > 1 ? "STEP" : "LINEAR");
        sampler.put("output", g.floatAccessor(values, outDim, outDim == 4 ? "VEC4" : "VEC3", false, null));
        samplers.add(sampler);
        channels.add(Map.of("sampler", samplers.size() - 1, "target", Map.of("node", node, "path", path)));
    }

    private static float[] flatten(List<Object> rows) {
        float[] out = new float[rows.size()];
        int n = 0;
        for (Object r : rows) {
            float[] v = (float[]) map(r).values().iterator().next();
            if (n + v.length > out.length) out = java.util.Arrays.copyOf(out, Math.max(out.length * 2, n + v.length));
            System.arraycopy(v, 0, out, n, v.length);
            n += v.length;
        }
        return n == out.length ? out : java.util.Arrays.copyOf(out, n);
    }

    private void build(Map<String, Object> root) {
        float scale = 1f;
        Map<String, Object> art = map(root.get("ArtToolInfo"));
        if (art != null && art.get("UnitsPerMeter") instanceof float[] upm && upm[0] > 0) scale = 1f / upm[0];

        Map<String, Object> rootNode = new LinkedHashMap<>();
        rootNode.put("name", "rnf_root");
        rootNode.put("rotation", Z_UP_TO_Y_UP);
        rootNode.put("scale", new float[]{scale, scale, scale});
        List<Object> rootChildren = new ArrayList<>();
        rootNode.put("children", rootChildren);
        int rootIndex = g.add("nodes", rootNode);
        g.json.put("scenes", List.of(Map.of("nodes", List.of(rootIndex))));
        g.json.put("scene", 0);

        int materialIndex = buildMaterial();
        Map<Object, Integer> meshCache = new java.util.IdentityHashMap<>();

        for (Object mo : list(root.get("Models"))) {
            Map<String, Object> model = map(mo);
            String modelName = String.valueOf(model.get("Name"));
            Map<String, Object> skeleton = map(model.get("Skeleton"));
            List<Object> bones = skeleton == null ? List.of() : list(skeleton.get("Bones"));

            Map<String, Object> modelNode = new LinkedHashMap<>();
            modelNode.put("name", modelName.startsWith("-tag ") ? "tag_" + modelName.substring(5) + "_placement" : modelName);
            applyTransform(modelNode, (Transform) model.get("InitialPlacement"));
            List<Object> modelChildren = new ArrayList<>();
            modelNode.put("children", modelChildren);
            rootChildren.add(g.add("nodes", modelNode));

            int[] boneNodes = new int[bones.size()];
            Map<String, Integer> boneIndexByName = new HashMap<>();
            for (int i = 0; i < bones.size(); i++) {
                Map<String, Object> bone = map(bones.get(i));
                String name = String.valueOf(bone.get("Name"));
                boneIndexByName.putIfAbsent(name, i);
                Map<String, Object> n = new LinkedHashMap<>();
                n.put("name", name.startsWith("-tag ") ? "tag_" + name.substring(5) : name);
                applyTransform(n, (Transform) bone.get("Transform"));
                boneNodes[i] = g.add("nodes", n);
                nodeByName.putIfAbsent((String) n.get("name"), boneNodes[i]);
            }
            for (int i = 0; i < bones.size(); i++) {
                int parent = ((int[]) map(bones.get(i)).get("ParentIndex"))[0];
                if (parent >= 0 && parent < bones.size()) childrenOf(boneNodes[parent]).add(boneNodes[i]);
                else modelChildren.add(boneNodes[i]);
            }

            for (Object mbo : list(model.get("MeshBindings"))) {
                Map<String, Object> mesh = map(map(mbo).get("Mesh"));
                if (mesh == null) continue;
                Map<String, Object> meshNode = new LinkedHashMap<>();
                meshNode.put("name", String.valueOf(mesh.get("Name")));
                Integer meshIndex = meshCache.get(mesh);
                boolean skinned = !list(mesh.get("BoneBindings")).isEmpty() && bones.size() > 0;
                if (meshIndex == null) {
                    meshIndex = buildMesh(mesh, boneIndexByName, skinned, materialIndex);
                    meshCache.put(mesh, meshIndex);
                }
                meshNode.put("mesh", meshIndex);
                if (skinned) meshNode.put("skin", buildSkin(bones, boneNodes));
                modelChildren.add(g.add("nodes", meshNode));
            }
        }
    }

    @SuppressWarnings("unchecked")
    private List<Object> childrenOf(int node) {
        Map<String, Object> n = (Map<String, Object>) g.array("nodes").get(node);
        return (List<Object>) n.computeIfAbsent("children", k -> new ArrayList<>());
    }

    private void applyTransform(Map<String, Object> node, Transform t) {
        if (t == null) return;
        if ((t.flags() & 1) != 0) node.put("translation", t.position());
        if ((t.flags() & 2) != 0) {
            float[] q = t.orientation();
            double len = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
            if (len > 1e-6) node.put("rotation", new float[]{(float) (q[0] / len), (float) (q[1] / len), (float) (q[2] / len), (float) (q[3] / len)});
        }
        if ((t.flags() & 4) != 0) {
            float[] m = t.scaleShear();
            float shear = Math.abs(m[1]) + Math.abs(m[2]) + Math.abs(m[3]) + Math.abs(m[5]) + Math.abs(m[6]) + Math.abs(m[7]);
            if (shear > 1e-3) warnings.add("shear ignored on node " + node.get("name"));
            node.put("scale", new float[]{m[0], m[4], m[8]});
        }
    }

    private int buildMaterial() {
        Map<String, Object> pbr = new LinkedHashMap<>();
        pbr.put("metallicFactor", 0.0);
        pbr.put("roughnessFactor", 0.85);
        if (textureUri != null) {
            int image = g.add("images", Map.of("uri", textureUri));
            int sampler = g.add("samplers", Map.of("magFilter", 9729, "minFilter", 9987, "wrapS", 10497, "wrapT", 10497));
            int texture = g.add("textures", Map.of("source", image, "sampler", sampler));
            pbr.put("baseColorTexture", Map.of("index", texture));
        }
        Map<String, Object> mat = new LinkedHashMap<>();
        mat.put("name", "skin");
        mat.put("pbrMetallicRoughness", pbr);
        return g.add("materials", mat);
    }

    private int buildMesh(Map<String, Object> mesh, Map<String, Integer> boneIndexByName, boolean skinned, int materialIndex) {
        List<Object> verts = list(map(mesh.get("PrimaryVertexData")).get("Vertices"));
        int n = verts.size();
        float[] pos = new float[n * 3], nrm = new float[n * 3], uv = new float[n * 2];
        int[] joints = new int[n * 4], weights = new int[n * 4];
        boolean hasNormal = false, hasUv = false;

        List<Object> bindings = list(mesh.get("BoneBindings"));
        int[] bindingToJoint = new int[bindings.size()];
        for (int i = 0; i < bindings.size(); i++) {
            String boneName = String.valueOf(map(bindings.get(i)).get("BoneName"));
            Integer j = boneIndexByName.get(boneName);
            if (j == null) {
                warnings.add("bone binding '" + boneName + "' not in skeleton");
                j = 0;
            }
            bindingToJoint[i] = j;
        }

        for (int v = 0; v < n; v++) {
            Map<String, Object> vert = map(verts.get(v));
            float[] p = (float[]) vert.get("Position");
            System.arraycopy(p, 0, pos, v * 3, 3);
            if (vert.get("Normal") instanceof float[] nn) { System.arraycopy(nn, 0, nrm, v * 3, 3); hasNormal = true; }
            if (vert.get("TextureCoordinates0") instanceof float[] t) { uv[v * 2] = t[0]; uv[v * 2 + 1] = t[1]; hasUv = true; }
            if (skinned) {
                int[] bi = vert.get("BoneIndices") instanceof int[] a ? a : new int[]{0, 0, 0, 0};
                int[] bw = vert.get("BoneWeights") instanceof int[] w ? w : new int[]{255, 0, 0, 0};
                int sum = 0, maxSlot = 0;
                for (int k = 0; k < 4; k++) {
                    int w = k < bw.length ? bw[k] : 0;
                    int b = k < bi.length ? bi[k] : 0;
                    joints[v * 4 + k] = (w > 0 && b < bindingToJoint.length) ? bindingToJoint[b] : 0;
                    weights[v * 4 + k] = w;
                    sum += w;
                    if (w > weights[v * 4 + maxSlot]) maxSlot = k;
                }
                if (sum == 0) weights[v * 4] = 255;
                else weights[v * 4 + maxSlot] += 255 - sum; // glTF wants the normalized weights to sum to 1
            }
        }

        Map<String, Object> attributes = new LinkedHashMap<>();
        attributes.put("POSITION", g.floatAccessor(pos, 3, "VEC3", true, 34962));
        if (hasNormal) attributes.put("NORMAL", g.floatAccessor(normalize(nrm), 3, "VEC3", false, 34962));
        if (hasUv) attributes.put("TEXCOORD_0", g.floatAccessor(uv, 2, "VEC2", false, 34962));
        if (skinned) {
            attributes.put("JOINTS_0", g.byteAccessor(joints, 4, "VEC4", false));
            attributes.put("WEIGHTS_0", g.byteAccessor(weights, 4, "VEC4", true));
        }

        Map<String, Object> topo = map(mesh.get("PrimaryTopology"));
        int[] indices = readIndices(topo);
        List<Object> primitives = new ArrayList<>();
        List<Object> groups = list(topo.get("Groups"));
        if (groups.isEmpty()) groups = List.of(Map.of("TriFirst", new int[]{0}, "TriCount", new int[]{indices.length / 3}));
        for (Object go : groups) {
            Map<String, Object> grp = map(go);
            int first = ((int[]) grp.get("TriFirst"))[0], count = ((int[]) grp.get("TriCount"))[0];
            int[] part = java.util.Arrays.copyOfRange(indices, first * 3, Math.min(indices.length, (first + count) * 3));
            Map<String, Object> prim = new LinkedHashMap<>();
            prim.put("attributes", attributes);
            prim.put("indices", g.indexAccessor(part));
            prim.put("material", materialIndex);
            primitives.add(prim);
        }
        return g.add("meshes", Map.of("name", String.valueOf(mesh.get("Name")), "primitives", primitives));
    }

    private static int[] readIndices(Map<String, Object> topo) {
        List<Object> rows = list(topo.get("Indices"));
        if (rows.isEmpty()) rows = list(topo.get("Indices16"));
        int[] out = new int[rows.size()];
        for (int i = 0; i < out.length; i++) {
            Object first = map(rows.get(i)).values().iterator().next();
            out[i] = ((int[]) first)[0];
        }
        return out;
    }

    private static float[] normalize(float[] v) {
        for (int i = 0; i < v.length; i += 3) {
            double l = Math.sqrt(v[i] * v[i] + v[i + 1] * v[i + 1] + v[i + 2] * v[i + 2]);
            if (l < 1e-8) { v[i + 1] = 1; continue; }
            v[i] /= l; v[i + 1] /= l; v[i + 2] /= l;
        }
        return v;
    }

    private int buildSkin(List<Object> bones, int[] boneNodes) {
        float[] ibm = new float[bones.size() * 16];
        List<Object> joints = new ArrayList<>();
        for (int i = 0; i < bones.size(); i++) {
            float[] m = (float[]) map(bones.get(i)).get("InverseWorldTransform");
            System.arraycopy(m, 0, ibm, i * 16, 16);
            ibm[i * 16 + 3] = 0; ibm[i * 16 + 7] = 0; ibm[i * 16 + 11] = 0; ibm[i * 16 + 15] = 1;
            joints.add(boneNodes[i]);
        }
        Map<String, Object> skin = new LinkedHashMap<>();
        skin.put("joints", joints);
        skin.put("inverseBindMatrices", g.floatAccessor(ibm, 16, "MAT4", false, null));
        return g.add("skins", skin);
    }
}
