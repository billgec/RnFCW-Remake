# Eigene Grafiken

Alles, was hier liegt, hat Vorrang vor `../original/`. Der relative Pfad muss gleich sein.

Beispiel: Die Haut des Speerwerfers ersetzen

    original/textures/men_ymjavelin_t.png   ← vom Konverter erzeugt
    overrides/textures/men_ymjavelin_t.png  ← eigene Version, wird stattdessen benutzt

Bei Einheiten- und Gebäudetexturen ist der **Alphakanal die Spielerfarben-Maske**:
voll deckend (Alpha 255) = Textur wie gemalt, durchsichtig = hier kommt die Spielerfarbe hin.
