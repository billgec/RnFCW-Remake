# Your own art

Anything placed here takes precedence over `../original/`, as long as the relative path
matches.

Example – replacing the javelin thrower's skin:

    original/textures/men_ymjavelin_t.png   <- written by convert.sh
    overrides/textures/men_ymjavelin_t.png  <- used instead

For unit and building skins the **alpha channel is the player-colour mask**: fully opaque
(alpha 255) keeps the painted texture, anything less lets the player colour through, and the
alpha gradient carries that garment's shading.
