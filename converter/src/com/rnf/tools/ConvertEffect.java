package com.rnf.tools;

import com.rnf.assets.DataSsaArchive;
import com.rnf.gltf.Gr2ToGltf;

import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Converts a single effect model together with its animations - effect models (rally flag,
 * banners) are rigged and only take their real shape once an animation plays; their bind
 * pose has the flag pole lying flat.
 *
 * <pre>ConvertEffect &lt;data.ssa&gt; &lt;outRoot&gt; &lt;models\x.gr2&gt; &lt;textures\y.dds|-&gt; [animations\z.gr2]...</pre>
 */
public final class ConvertEffect {

    public static void main(String[] args) throws Exception {
        Path outRoot = Path.of(args[1]);
        try (DataSsaArchive archive = new DataSsaArchive(args[0])) {
            String textureUri = null;
            if (!args[3].equals("-")) textureUri = "../textures/" + Convert.texture(archive, outRoot, args[3]);
            Map<String, byte[]> animations = new LinkedHashMap<>();
            for (int i = 4; i < args.length; i++) {
                animations.put(Convert.baseName(args[i]), archive.readFile(args[i]));
            }
            String name = Convert.baseName(args[2]) + ".glb";
            for (String warning : Gr2ToGltf.convert(archive.readFile(args[2]), textureUri, animations,
                    outRoot.resolve("models").resolve(name))) {
                System.err.println("warn: " + warning);
            }
            System.out.println("effect " + name + " with " + animations.size() + " animation(s)");
        }
    }
}
