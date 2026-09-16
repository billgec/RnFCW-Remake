# Rise & Fall: Civilizations at War — Dateiformate (Analyse-Notizen)

Stand: 2026-08-28. Alles unten wurde am vorliegenden Verzeichnis verifiziert,
sofern nicht anders vermerkt.

## ZL01-Blöcke (Basisbaustein)

Kommt in `.scn`, `.ees` und in den Payloads der `.ssa`-Archive vor:

```
u32  blockSize        (= 12 + Länge des Deflate-Streams)
"ZL01"
u64  rawSize          (Größe nach dem Entpacken)
...  zlib-Deflate-Stream
```

Verifiziert: `rawSize` stimmt bei allen 9 Blöcken einer Testdatei exakt mit der
entpackten Länge überein.

## `.scn` (Szenario) und `.ees` (Spielstand)

Identisches Format. Unkomprimierter Kopf mit lesbaren Strings, danach mehrere
ZL01-Blöcke, dazwischen/danach unkomprimierte Bereiche.

```
u32  fileSize - 4     (verifiziert an 6 Dateien)
u32  nameLen + Name   ("bence123.ees")
u32  descLen + Beschreibung
...  Spielerliste (Name, Zivilisation, Team, Farbe, CP-Flag ...)
u32  lenr + Zeitstempel ("Fri Mar 11 18:20:10 2022")
...  Spielerslots einzeln, danach Optionen, Kartenname ("(5) Gorges.scn")
...  ZL01-Blöcke
```

Blockinhalte in einem typischen Spielstand:

| Block | Größe   | Inhalt                                              |
|-------|---------|-----------------------------------------------------|
| 0     | 15 B    | Header-Flags                                        |
| 1     | 10,2 MB | Terrain/Kachelgitter (beginnt mit `u32 160, u32 160` = Kartengröße) |
| 2     | 1,2 kB  | Trigger, mit Klartextnamen (`<Trigger 0>`, `<No Build All Human Add>`) |
| 3–4   | klein   | Kamera / Spielerpositionen                          |
| 5     | 2,7 MB  | Einheiten- und Objektzustand (Float-Arrays)         |
| 6     | 274 kB  | Effekte, enthält Namen wie `sfx_ycampfire`          |
| 7–8   | klein   | Statistik / Diplomatie                              |

## `.ssa` (Archiv)

```
"rass" | u32 version | u32 (0) | u32 dirSize
Einträge: u32 nameLen | Name (nameLen Bytes, NUL-gepolstert)
          u32 dataStart | u32 dataEnd | u32 rawSize
```

* `Data/Campaigns/Alexander.ssa` — Version 1, 639 Einträge (541 mp3, 85 wav, 12 scn, 1 txt)
* `Data/Campaigns/Cleopatra.ssa` — Version 1, 332 Einträge
* `Data/data.ssa` — **Version 3, verschlüsselt.** Entropie 7,95 über den gesamten
  Bereich, kein zlib. Das Verzeichnis ist nicht ohne Reverse Engineering der
  Engine lesbar.

## `data.ssa` (Version 3) — vollständig entschlüsselt

Stand 2026-09-03: Die Verschlüsselung ist gebrochen (statische Analyse von
`LowLevelEngine.dll` mit Ghidra 12.1.3 + radare2 6.2.0, RiseAndFall.exe
`FSArchive::Open` → `ReadHeader` → `ReadFAT` → `ReadFATFile`). Werkzeug:
[`tools/rnf_ssa3.pl`](rnf_ssa3.pl) (`list` / `extract` / `cat`).

**Header** (12 Bytes, danach folgt ein separat gelesenes u32 `fatSize`):

```
"rass" | u32 version(=3) | u32 reserved(=0) | u32 fatSize
```

**Verzeichnis** (`fatSize` Bytes ab Offset 16):

1. Die ersten 32 Bytes werden mit einem **festen 32-Byte-XOR-Schlüssel**
   entschlüsselt, der in `LowLevelEngine.dll` bei RVA `0x1c35f4` liegt:
   `64 34 68 82 55 87 49 32 d3 02 01 b2 12 73 13 ff 59 21 39 57 54 30 ef a3 56 23 99 48 98 b1 a9 48`
   (`buf[i] ^= key[i]` für `i = 0..31`).
2. Nach dem Entschlüsseln stehen an Offset 0 vier Bytes `compLen` (u32),
   gefolgt von einem **Standard-zlib-Stream** (`inflateInit_`/`inflate`,
   Versionsstring `"1.1.4"` — dieselbe `FUN_1012eb70`-Wrapperfunktion wie
   die ZL01-Blöcke). Ergebnis: das komplette Klartext-Verzeichnis.

**Verzeichniseintrag** (nach dem Entpacken, pro Datei):

```
u32  nameLen                  (inkl. NUL-Terminator)
     name  (nameLen Bytes, NUL-terminiert, davor mit 0xFF aufgefüllt)
u32  start                    (absolute Position der Rohdaten in data.ssa)
u32  end                      (start + Größe-auf-Platte)
u32  raw                      (Größe-Hinweis, NICHT zuverlässig die entpackte
                                Größe — siehe unten)
u32[8]  perFileXorKey         (32 Bytes, individueller Schlüssel NUR für diese Datei)
```

12.150 Einträge in der Vollversion, vollständig durchparsbar bis zum letzten Byte.

**Dateiinhalt** (`FSArchive::ReadFATFile`, `UDataCompression`):

1. `onDisk = end - start` Bytes ab `start` lesen.
2. Die ersten `min(onDisk, 32)` Bytes mit dem **eigenen** 32-Byte-Schlüssel
   dieser Datei XOR-entschlüsseln (nicht der feste FAT-Schlüssel von oben!).
3. `UDataCompression::GetIsCompressed` prüft die ersten 4 Bytes:
   - Tag `"ZL01"` → `Decompress` ruft `FUN_1012eb70(dest, &destLen, buf+12, onDisk-12)`
     — Bytes `[4:12)` = u64 rawSize, ab Byte 12 ein normaler zlib-Stream.
   - Tag `"PK01"` → laut `GetIsCompressed` ebenfalls "komprimiert", aber
     `Decompress` behandelt diesen Tag **nicht** (gibt Fehler 0x15 zurück) —
     in der Praxis bisher nicht beobachtet, evtl. ungenutzter Legacy-Pfad.
   - Kein erkannter Tag → Datei ist unkomprimiert, die (bereits XOR-entschlüsselten)
     Rohbytes sind der Inhalt.

Verifiziert an `db\dbobjects.dat` (6,2 MB entpackt, lesbare Klartext-Namen wie
`"A - Inf01 - Javelin Thrower (Greek)"`), `db\dbtechtree.dat` (1,2 MB) und
mehreren `.udf`/`.gr2`-Einheitendateien — alle sauber entpackt, Strings korrekt.

## Datenbanktabellen — Registry (Tabellen-ID → Datei → Parser-Funktion)

Jede `dbXXX.dat`-Tabelle wird über eine **eigene, handgeschriebene
Parser-Funktion** geladen (kein generisches/selbstbeschreibendes Format,
trotz `EEDatabase`/`EEDatabaseTableNode`-RTTI-Namen). Zentrale Ladefunktion:
`RiseAndFall.exe : FUN_00718590` (ruft für jede Tabelle
`FUN_00713200(tableId, FUN_005f8fd0)`; `FUN_005f8fd0` ist ein Dispatcher, der
per `tableId` in die passende Parser-Funktion springt). Adressen beziehen
sich auf `RiseAndFall.exe`, geladen als PE mit Standard-Basisadresse in Ghidra:

| ID  | Datei                                  | Parser-Funktion |
|-----|-----------------------------------------|------------|
| 1   | db\dbmusic.dat                          | 0x005fe110 |
| 2   | db\dbobjects.dat                        | 0x005f8ef0 |
| 3   | db\dbgraphics.dat                       | 0x005fccc0 |
| 5   | db\dbButtons.dat                        | 0x005f4bc0 |
| 6   | db\dbtechtree.dat                       | 0x008d8260 |
| 9   | db\dbfamily.dat                         | 0x00606ac0 |
| 11  | db\dbaiunittargeting.dat                | 0x005f2250 |
| 12  | db\dbterrain.dat                        | 0x00605ba0 |
| 14  | db\dbterrainType.dat                    | 0x006068e0 |
| 15  | db\dbworld.dat                          | 0x0060de70 |
| 16  | db\dbrandommap.dat                      | 0x006000e0 |
| 17  | db\dbcivilization.dat                   | 0x00bc2cd0 |
| 20  | db\dbweapontohit.dat                    | 0x0060d310 |
| 21  | db\dbcalamity.dat                       | 0x00407ae0 |
| 22  | db\dbunitset.dat                        | 0x006ef030 |
| 23  | db\dbareaeffect.dat                     | 0x00baf8c0 |
| 25  | db\dbupgrade.dat                        | 0x0060c5b0 |
| 26  | db\dbcpbehavior.dat                     | 0x005f74b0 |
| 27  | db\dbambientsounds.dat                  | 0x006caf80 |
| 28  | db\dbAnimals.dat                        | 0x005f3370 |
| 29  | db\dbUnitBehavior.dat                   | 0x0060d1c0 |
| 30  | db\dbStartingResources.dat              | 0x00602990 |
| 31  | db\dbGameVariant.dat                    | 0x005fbee0 |
| 32  | db\dbpremadecivs.dat                    | 0x00bc5010 |
| 33  | db\dbcliffterrain.dat                   | 0x00605f40 |
| 34  | db\dbcivpowers.dat                      | 0x00bc5cb0 |
| 38  | db\dbnewgfxeffecttable.dat              | 0x00619470 |
| 39  | db\dbphoenixcivtable.dat                | 0x005ff420 |
| 40  | db\dbcivspecificunitdefines.dat         | 0x005f60a0 |
| 41  | DB\dbuihotkey.dat                       | 0x00b8c310 |
| 52  | DB\dbcivspecai.dat                      | 0x005f7380 |
| 53  | db\dbcrewedunitdetails.dat              | 0x005fa830 |
| 54  | db\dbterrainsettable.dat                | 0x00603ec0 |
| 55  | db\dbsoundgroups.dat                    | 0x006014c0 |
| 56  | db\dbtpwalkeffects.dat                  | 0x0060b800 |
| 57  | db\dbtpmeleeattackeffects.dat           | 0x006093d0 |
| 58  | db\dbflora.dat                          | 0x005fb530 |

Fehlende IDs (4, 10, 51 u. a.) laden Tabellen ohne Namens-String in Reichweite
der Analyse (z. B. `db\dbevents.dat`, `db\dbeffects.dat` — separater Codepfad
über `FSPath::FindFile` statt `FUN_00713200`) oder wurden nicht aufgelöst.

### `db\dbobjects.dat` — Objekt-Tabelle

`FUN_005f8ef0`: liest `u32 count`, dann pro Objekt exakt **2012 Bytes**
(`0x7dc`) als ein Block über `FUN_005fa9e0` → `FSFileSpec::Read(ptr, 0x7dc)`.
Kein Feld-für-Feld-Parsing im Code sichtbar — die 2012 Bytes werden als
rohes C-Struct interpretiert, dessen einzelne Felder über das ganze Binary
verteilt gelesen/geschrieben werden (kein einzelner "Definiert-hier"-Ort).

Empirisch (Byte-Diff zwischen benachbarten, strukturell fast identischen
Datensätzen `"...Scaffolding - 2 Story Crane (Greek)"` und
`"...Scaffolding - 2 Story Platform (Greek)"`, beide 2012 Bytes lang und
im Archiv direkt hintereinander gespeichert):

* Name-Feld beginnt ca. 300 Bytes vor Datensatzende-relativ (0xFF-Padding
  davor, `\0`-Padding danach, siehe oben).
* Mehrere u32-Felder bei relativen Offsets **400, 416, 596, 604, 1212**
  (relativ zum Namensbeginn) sind zwischen benachbarten Datensätzen exakt
  **um 1 höher** (z. B. 2943 → 2944) — sehr wahrscheinlich separate,
  fortlaufend vergebene IDs in gemeinsame Ressourcentabellen (Name-String,
  Beschreibung, Icon, Sound o. ä.), nicht zwingend eine einzelne "Objekt-ID".
* **Kein einzelnes Bit/Byte gefunden, das eindeutig "nur in Kampagne/Szenario
  verfügbar" bedeutet** — Crane und Platform sind bis auf Name und diese
  laufenden IDs strukturell identisch.
* Bestätigt: `"A - Inf01 - Javelin Thrower (Greek)"`,
  `"A - Inf01 - Javelin Thrower (Persian)"`, `"A - PROJ - Javelin"` sowie
  `"A - b  Scaffolding - 2 Story Crane (Egypt/Greek/Persian/Rome)"` sind
  vollständig für die vier Standard-Zivilisationen definierte Objekte
  (nicht auf eine Kampagnen-Zivilisation beschränkt).

### `db\dbtechtree.dat` — Tech-/Epochen-Tabelle

`FUN_008d8260`: liest **14 Epochen-Datensätze** über `FUN_008dff40`
(≈ 620 Zeilen dekompilierter Code, u. a. zwei count-präfixierte u32-Arrays,
ein dichtes Struct mit Dutzenden Bitflags sowie 11 verschachtelte
Unter-Einträge pro Epoche via `FUN_008df3f0`). Letztere Funktion baut
sichtbar einen **Abhängigkeitsgraphen** zwischen Epochen/Techs auf
(Vergleiche über mehrere verschachtelte Strukturzeiger, keine flache Liste).

→ Dies ist **kein einfaches "Flag pro Objekt"-Format**, sondern ein
zusammenhängender Graph. Die Objekt-ID der Crane taucht an zwei Stellen in
`dbtechtree.dat` auf: an einer Stelle ist die Umgebung byte-identisch zur
Platform-Variante (derselbe Slot, nur die ID unterschiedlich), an der
anderen unterscheiden sich zwei Zahlenfelder (10000 vs. 20000 und 174 vs.
2839) klar — deren Bedeutung war mit reinem Byte-Vergleich nicht sicher zu
bestimmen. Um das vollständig und sicher änderbar zu machen, müsste
`FUN_008dff40` und `FUN_008df3f0` feldweise durchanalysiert werden
(deutlich größerer Aufwand als das Knacken der Archiv-Verschlüsselung).

### `dbtechtree.dat` — Trainierbare-Einheit-Einträge (2026-09-03, per Byte-Vergleich geknackt)

Wichtige Korrektur zur vorherigen Analyse: Die "Objekt-ID", die Baulisten
tatsächlich referenzieren, ist **nicht** das Feld bei Namens-relativem
Offset `+100` (das ist vermutlich eine andere, unabhängige laufende
Nummer), sondern das Feld bei Offset `+912` — bestätigt, weil dieser Wert
sowohl in `dbtechtree.dat` als auch in der Bauliste des jeweiligen
Gebäudes (`dbobjects.dat`) identisch wieder auftaucht.

Pro trainierbarer Einheit gibt es in `dbtechtree.dat` **genau einen** festen
44×u32-Eintrag (Beispiel: „Spear Infantry (Level 1 Greek)", id=6882,
gefunden per Volltextsuche nach `pack("V", $id912Wert)`):

```
[-1] parentTechId        (z. B. 3690 — Kategorie/Gruppe)
[ 0] unitId               (= Feld+912 im Objekt-Datensatz, s.o.)
[ 1] 5                    (konstant bei allen geprüften Einheiten)
[ 2] 14                   (konstant)
[ 3] -1                   (Sentinel/„unset", konstant bei funktionierenden Einträgen)
[ 4] -1                   (Sentinel/„unset")
[ 5] variiert              (z. B. 0 oder 25 — Bedeutung unklar)
[ 6] 0                    (konstant)
[ 7] variiert              (z. B. 45–55 — vermutlich Trainingszeit oder Bevölkerungskosten)
[ 8] 0
[ 9] 0
[10] Kosten                (z. B. 19000–24000 — Ressourcenpreis, vermutlich ×100)
[11..14] 0
[15] unitspezifische ID    (nahe an [18], evtl. String-/Icon-Referenz)
[16] unitspezifische ID
[17] 1                    (konstant)
[18] unitspezifische ID
[19] 1                    (konstant)
[20..23] 0
[24] -1                   (konstant, Sentinel)
[25] 3                    (konstant bei funktionierenden Einträgen)
[26] -1                   (konstant, Sentinel)
[27..28] 0
[29] 5                    (konstant bei funktionierenden Einträgen)
[30] unitspezifische ID    (fortlaufend zwischen ähnlichen Einheiten, z. B. 14995/14996)
[31] 0
[32] 24003                (identisch bei ALLEN geprüften Einheiten — evtl. Barracks-/UI-Referenz)
[33] 24007                (identisch bei ALLEN geprüften Einheiten)
[34] unitspezifische ID
[35] unitspezifische ID
[36] 0
[37..40] 1.0f ×4           (Skalierungsfaktoren, konstant)
[41] 1                    (konstant bei funktionierenden Einträgen — s. u.)
[42..43] 0
```

**Fallstudie Javelin Thrower (Greek):** Der Eintrag existierte bereits
(unitId 6514 an Dateiposition 813704), aber mit stark abweichenden Werten
gegenüber zwei funktionierenden Kontroll-Einheiten (Sword/Spear Infantry
Level 1, beide garantiert normal trainierbar):

| Feld | Javelin (vorher) | Sword Inf. | Spear Inf. |
|------|------------------:|-----------:|-----------:|
| [3]  | 0                 | -1         | -1         |
| [4]  | 0                 | -1         | -1         |
| [10] (Kosten) | 0        | 19000      | 24000      |
| [25] | 0                 | 3          | 3          |
| [29] | 0                 | 5          | 5          |
| [41] | **65793** (0x00010101) | 1     | 1          |

`[41]=65793` ist besonders auffällig: als 4 Bytes gelesen (`01 01 01 00`)
hat es zwei zusätzliche Bits gesetzt, die bei beiden funktionierenden
Kontroll-Einheiten (`00 00 00 01`) fehlen — starker Kandidat für ein
Sichtbarkeits-/Freischalt-Flag, auch wenn die genaue Bit-Bedeutung nicht
über Code-Analyse verifiziert wurde, nur über den Strukturvergleich.

### Feld-Layout in `dbobjects.dat` — **verifiziert**

Innerhalb des 2012-Byte-Records (Offsets relativ zum Recordbeginn):

| Offset | Typ | Bedeutung |
|--------|-----|-----------|
| `+120`  | `u32`   | **Trefferpunkte** |
| `+196`  | `u32`   | **Angriffsschaden** |
| `+300`  | `u32`   | **Button-Index** in `dbButtons.dat` (Icon + Reihenfolge in der UI) |
| `+908`  | `u32`   | **Anzahl** der Bauliste-Einträge, die das Spiel liest |
| `+912`  | `u32`   | **eigene Objekt-ID** (Querverweis aus `dbtechtree.dat` und Baulisten) |
| `+1212` | `u32[]` | die Bauliste (Objekt-IDs), danach `-1`-Padding |

`+120`/`+196` gefunden über eine Einheitenreihe, deren Werte zwangsläufig mit
der Stufe steigen (Sword Infantry L1/L3/L5 Greek): nur diese beiden Felder
steigen streng monoton *und* ergeben im Quervergleich sinnvolle Zahlen —
War Elephant 2500 HP / 100 Schaden gegen Sword Infantry L1 380/18,
Archer L1 200/29, Javelin Thrower 345/10.

`+300` bestätigt durch Nachschlagen in `dbButtons.dat` (2921 Sätze à 232 Byte):
Index 28 → „Javelin Thrower (Greek)" + `textures\but_yMJavelinT`,
105 → Archer L1 + `but_yGArcher1T`, 108 → Spear Infantry, 111 → Sword Infantry.
Der Index bestimmt offenbar auch die **Sortierung in der Ausbildungs-UI** — der
Javelin (28) erscheint vor allen Kasernen-Einheiten (105–111). Umsortieren
hieße also, auf einen anderen Button-Satz zu zeigen, und damit auch ein
anderes Icon zu bekommen.

Gegengeprüft an **allen 299** Records, die eine Liste führen: bei jedem sind
genau die ersten `n` Slots ab `+1212` belegt und Slot `n` ist `-1` — **null
Abweichungen**. Werkzeug: `tools/rnf_buildlist.pl` (`list` / `add`).

**Die Falle ist der Zähler bei `+908`.** Ein früherer Versuch trug `6514`
korrekt in den ersten freien Slot (`+1496`) der `Barracks (MP) (Greek)`
(Record-Offset 388320) ein, ließ `+908` aber auf `71` — das Spiel las nur
71 Slots und hat den Eintrag nie gesehen. Genau deshalb blieb der Patch
wirkungslos. `rnf_buildlist.pl add` setzt beides zusammen.

**Wichtiger Befund zur Ausgangsfrage:** `tools/rnf_whoreferences.pl` zeigt,
dass die ID `6514` (Javelin Thrower Greek) in `dbobjects.dat` von
**keinem einzigen** Objekt referenziert wird — zum Vergleich: Spear Infantry
(`6882`) wird von 34 Records geführt, darunter `Barracks (MP) (Greek)` und
`Barracks (SP) (Greek)`. Der Javelin Thrower ist also **nirgends im Spiel
rekrutierbar, auch nicht in der Kampagne**; dort wird er nur fertig
platziert. Es gibt somit keine funktionierende Vorlage zum Kopieren — die
Einheit muss echt neu in eine Bauliste aufgenommen werden.

**Angewendeter Fix** (Tech-Tree via `tools/rnf_techpatch.pl`): `[3]`,`[4]`
auf `-1`, `[10]` auf `20000` (Kosten — plausibel gewählt, keine „entdeckte"
Zahl), `[7]` Bauzeit auf `45` (vom Spear Infantry übernommen; stand vorher
auf `0`), `[25]`→`3`, `[29]`→`5`, `[41]`→`1`. Bauliste via
`rnf_buildlist.pl add` in `Barracks (MP) (Greek)` (Record 388320) **und**
`Barracks (SP) (Greek)` (Record 5032016), jeweils inklusive Zähler.
Ergebnis: 10 geänderte Bytes gegenüber dem Original.

**Javelin Thrower (Persian)** (id `6870`, Record 4422380): Tech-Baum-Eintrag
war hier schon fast intakt (Kosten `28000`, Bauzeit `40`, `[3]`/`[4]` schon
`-1`) — nur die Bauliste fehlte, exakt dieselbe Falle. Bewusst **nicht** in
die Kaserne, sondern in die **Archery Range** gepackt (MP: Record 5484716,
SP: Record 780660) — Wurfwaffe, kein Nahkampf, passt dort eher rein als bei
den Griechen (die stehen der Einfachheit halber in der Spartan Academy statt
der Kaserne, s.o.). Schaden `[196]` ebenfalls von `10` auf `32` angehoben
(gleiche Begründung wie beim griechischen Pendant). Icon (`+300` → Button
2460) ist geteilt mit dem griechischen Javelin (`but_yMJavelinT`) — die
Perser haben nie ein eigenes bekommen.

### Mauern haben ~12 Varianten pro Zivilisation — eine zu patchen reicht nicht

Erster Patch-Versuch (nur `Wall Plain (MP)` + `Wall Straight`) zeigte im Spiel
**nichts**. Grund: pro Zivilisation existieren rund ein Dutzend eigenständige
Mauer-Datensätze — `Plain`/`Straight`/`Corner`/`Narrow`, jeweils zusätzlich als
`(MP)`, `(SP)`, `(Scenario)` und `(Deform)`. Welchen davon man im Spiel
anklickt, hängt davon ab, wie die Mauer gesetzt wurde: **in einer Reihe gebaute
Mauern werden zu den `(Deform)`-Varianten** (aneinander angepasste Stücke), und
das sind komplett andere Records mit eigener Bauliste. `tools/rnf_wallmenu.pl`
patcht deshalb alle Mauer-Records einer Zivilisation in einem Durchlauf
(54 Records über alle vier Zivilisationen).

Zwei Mauer-Records haben Zähler `0` und damit gar kein Menü
(`Wall Narrow (SP) (Greek)`, `Wall Straight (SP) (Greek)`) — die überspringt
das Werkzeug.

### Verworfene Hypothesen zur Sichtbarkeit (dokumentiert, damit sie niemand nochmal prüft)

* **`field3`/`field4` = `-1` bedeutet „funktioniert"** — falsch. Die Tore
  arbeiten mit `0`/`0`, die Leiter mit `-1`/`-1`, beide sichtbar. Die
  Korrelation beim Javelin war Zufall.
* **Der Tech-Baum-Eintrag entscheidet** — falsch. Differenzanalyse über alle
  44 Felder von vier funktionierenden gegen drei nicht funktionierende
  Einträge: **kein einziges Feld** trennt die Gruppen sauber.
* **`field[-1]` ist ein Eltern-/Voraussetzungsknoten mit Objekt-ID** — falsch.
  Die Werte lösen sich zu unsinnigen Objekten auf (Statue Glory Egypt als
  „Elternknoten" des griechischen Javelin). Das ist ein eigener ID-Raum.
* **Mein Patch wird gar nicht geladen** — falsch, per Disassembly widerlegt:
  `FUN_00a1dd00` ist der Konstruktor des Laufzeit-Templates und kopiert
  Zähler (`+0x38C`) und Liste (`+0x4BC`) aus dem Rohdatensatz in ein
  Laufzeit-Array bei `template+0x5c`. Gefunden durch Suche nach Funktionen,
  die **beide** Offsets als Immediate referenzieren (`FindBuildListCode.java`,
  genau ein Treffer unter 2,37 Mio. Instruktionen).

### Montage: `Wall Siege Platform` ist der Montagepunkt, nicht die Mauer

Nach dem Varianten-Patch **erscheint** das Tower Catapult im Mauer-Menü und
lässt sich bauen — es spawnt dann aber **neben** der Mauer auf dem Boden
statt darauf. Erklärung: die nackte Mauer ist kein Montagepunkt. Die
vorgesehene Kette ist zweistufig und in Vanilla vollständig verdrahtet:

```
Mauer  --baue-->  Wall Siege Platform  --baue-->  Tower Catapult   (montiert)
Trireme  --baue-->  Naval Onager                                   (montiert)
```

Belegt: alle skirmish-relevanten `Wall Siege Platform`-Varianten (Greek/
Egypt/Rome/Persian, jeweils auch `(Deform)`) führen von Haus aus genau einen
Eintrag — das Tower Catapult ihrer Zivilisation. Die Plattform ist also das
Gegenstück zum Schiff: dort sitzt die Waffe. Der direkte Eintrag im
Mauer-Menü umgeht diesen Montagepunkt und erzeugt deshalb ein
Boden-Katapult.

Leer waren nur die `(SP)`- und `(Scenario)`-Plattform-Varianten (6 Records) —
nachgetragen, damit Szenarien dieselbe Kette haben.

**Schiffsseite:** Der `Naval Onager` hängt in Vanilla ausschließlich an der
**Trireme** (`A - s03a`, inkl. `(unpacked)`), nicht an Bireme oder Galley —
offenbar Absicht, nur das größte Schiff trägt Artillerie.

**Naval Onager auch auf Mauern** (Nutzer berichtet, dass die Kampagne das so
zeigt): per `tools/rnf_addbuildable.pl` in **alle 14**
`Wall Siege Platform`-Varianten aller vier Zivilisationen eingetragen, neben
dem dort bereits vorhandenen Tower Catapult. In `dbobjects.dat` referenziert
den Onager sonst **kein** Nicht-Schiff — in der Kampagne dürfte er also
direkt per Szenario platziert statt gebaut werden. Gute Vorzeichen für das
Montieren: gleicher Kategoriecode `f1=5` wie das Tower Catapult, das auf der
Plattform nachweislich korrekt aufsitzt; Werte plausibel (Bauzeit 300,
Kosten 75000 gegen 200/50000 beim Katapult, bei 350 statt 200 Schaden).
**Ingame noch nicht bestätigt.**

`db\dbcrewedunitdetails.dat` (83 Sätze à 144 Byte) wäre der naheliegende Ort
für die Montage-/Besatzungsregeln, benutzt aber offenbar einen anderen
ID-Raum — eine Suche nach bekannten Objekt-IDs über alle 36 u32-Felder pro
Satz ergab nur einen offensichtlichen Zufallstreffer. Nicht weiter verfolgt.

### Offene Spur: „Building SiegeXX - Y" als eigentliches Bauobjekt

Jede Belagerungswaffe, die ein Arbeiter tatsächlich errichten kann, existiert
doppelt: als Baustellen-Objekt `A - b  Building SiegeXX - <Name> (<Civ>)` und
als fertige Einheit `A - SiegeXX - <Name> (<Civ>)`. Für **Tower Catapult** und
**Archimedes Claw** gibt es *kein* `Building`-Gegenstück — sie existieren nur
als fertige Einheit. Da alle in Vanilla vorhandenen Mauer-Menüeinträge
Gebäude sind (`A - b  ...`), ist die naheliegende Erklärung, dass das Menü nur
Bauobjekte akzeptiert und die beiden deshalb nie funktionierten, obwohl sie
seit jeher in den Listen stehen.

**Kontrollversuch mitgepatcht:** zusätzlich zu den beiden Einheiten wurde pro
Zivilisation ein nachweislich errichtbares Belagerungs-Bauobjekt in dieselben
Menüs gelegt (Greek `Building Siege02a - Ballista` id 7132, Egypt
`Building Siege03a - Catapult` id 9540, Persian `Building Siege03a - Onager`
id 9539, Rome `Building Siege02b - Ballista` id 7133). Erscheint im Spiel nur
dieses und nicht Katapult/Klaue, ist die Objektart bestätigt als Ursache.

### Tower Catapult / Archimedes Claw direkt ins Mauer-Menü gepatcht

Trotz der oben beschriebenen, scheinbar bereits vollständigen Kette
(`Wall Plain (MP)` → `Wall Siege Platform` → `Tower Catapult`, sowie
Archimedes Claw + Tower Catapult bereits in der Arbeiter-Bauliste) hat der
Nutzer bestätigt, dass beides im Skirmish nicht funktioniert. Statt der
mehrstufigen/indirekten Kette zu vertrauen: beide Einheiten direkt in die
Bauliste von **`Wall Plain (MP)`** *und* **`Wall Straight`** gepatzt (beide
Mauer-Objekttypen hatten bis dahin ein identisches Menü — Ladder/Gates/
Siege-Platform, aber getrennte Records, also getrennt patchen nötig), für
alle vier Zivilisationen. Zusätzlich im Tech-Baum: `field3`/`field4` bei
6 von 8 betroffenen Einträgen standen noch auf `0` statt `-1` (dasselbe
Muster wie beim Javelin) — nur die persischen Versionen beider Einheiten
hatten das schon korrekt. Kosten/Bauzeit waren bei allen acht bereits
sinnvoll gesetzt (Catapult 50000/200, Claw 40000/100) und wurden nicht
verändert. Ergebnis: 104 Bytes Diff in `dbobjects.dat`, 70 Bytes in
`dbtechtree.dat` (Stand nach diesem Patch).

**"Thracian Siege Tower"** — korrekter Name bestätigt (Nutzer hat
nachgesehen), aber intern noch nicht sicher identifiziert. Der Anzeigename
existiert als UTF-16-String in `Language2.dll` (nicht in `dbobjects.dat`
oder `dbButtons.dat` — reine Lokalisierungs-Zeichenkette, referenziert über
eine numerische "Bad String(NNNN)"-ID, die `db\string-graphic info.txt`
Objekten zuordnet). Positionsbasierte Vermutung (zwischen den bekannten
IDs 2210=Trireme und 2212=Ladder Guy, also ID 2211) hat **keinen** Treffer
in der Mapping-Tabelle ergeben — offen. Kandidat für einen erneuten
Versuch: `A - Siege00 - Siege Tower (SP) (Persian) (Griffin)` (dbButtons
Index 403) — eine Sondervariante mit Codenamen, die sonst nirgends auftaucht.

### Bannerträger-Aura — weiter erfolglos, aber jetzt mit echtem Ghidra-Befund

Per Ghidra-Headless-Skript (`FindAuraSymbols.java`,
`DumpMoraleRefs.java`/`DumpMoraleGetter.java` unter `D:\rnf_re\scripts\`,
gegen das bereits vorhandene analysierte Projekt `D:\rnf_re\proj\RNF`)
bestätigt: die C++-RTTI-Klassennamen `EEAreaEffectTemplate`,
`EECCApplyAreaEffect`, `EEZoneAreaEffectContainer` und insbesondere
**`EEZoneMoraleAreaEffectContainer`** existieren wirklich in
`RiseAndFall.exe` — das Aura-System ist also real. Die einzige Spur, die
sich bis zu einer Funktion zurückverfolgen ließ (`FUN_00ba0260`, referenziert
über den String `"morale"` in einem UI-Tooltip-Textparser), erwies sich als
Sackgasse: sie formatiert einen Bevölkerungs-Straftext
(`sprintf` mit Abzug `-50`), liest also aus dem Tooltip-Parser-Kontext,
nicht aus einem Einheiten-Record. Die eigentliche Anwendung der Aura liegt
vermutlich in `LowLevelEngine.dll` (viele `EE`-Klassen sind dort
implementiert) und wurde noch nicht lokalisiert — das bräuchte einen
weiteren, gezielten Disassemblier-Durchgang dort.

### Andere reine Kampagnen-Einheiten — Katalog

`tools/rnf_phantomunits.pl` verallgemeinert den obigen Fund: baut eine
id→Name-Tabelle, sammelt alle Namen, die wie eine gestufte Kampfeinheit
aussehen (`Inf01`/`Arc03`/`Cav05`/`Siege02a`-Muster, oder benannte Fahrzeuge
wie Chariot/Camel), und zählt in **einem** Durchlauf, wie oft jede davon
irgendwo im File referenziert wird. Ergebnis an diesem `dbobjects.dat`:
**289 Kandidaten, 96 davon nirgends referenziert** (reine Phantome, exakt
wie der Javelin Thrower vorher).

Grobe Einordnung der 96 (nicht einzeln durchgetestet):

* **Ladder-Mechanik (Belagerungsleitern)** — `Ladder Unit (Greek/Egypt)`,
  `Ladder Crew - Hold/Shield` (Greek/Egypt/Persian/Rome — **vier**
  Zivilisationen, keine fünfte; siehe „Gibt es eine fünfte Zivilisation?"
  unten), `Ladder (UnPack)(no move)` — laut Nutzer im normalen Skirmish
  bereits vorhanden und nutzbar. Erklärt sich vermutlich dadurch, dass diese
  per Fähigkeit (z. B. „Leiter an Mauer anlegen" bei bestehenden
  Belagerungseinheiten) erzeugt werden statt über eine Bauliste trainiert zu
  werden — `rnf_phantomunits.pl` prüft nur Baulisten-Referenzen, nicht
  fähigkeitsbasiertes Spawnen. Keine weitere Aktion nötig.

### Gibt es eine fünfte (antike) Zivilisation, z. B. Mazedonien?

**Nein**, nicht als eigene Fraktion. In `dbobjects.dat` kommt „Macedon"
nirgends als Namens-Suffix vor — nur die vier bekannten: `Greek` (356×),
`Persian` (402×), `Egypt` (356×), `Rome` (252×). Das interne Präfix `ym`
(„young Macedon"?) ist einfach der Asset-Code für das, was dem Spieler als
„Greek" angezeigt wird — passt zu Alexander (dem Mazedonier) als Helden
dieser Fraktion. `db\dbpremadecivs.dat` enthält zwar einen Eintrag „Classical
Greece", aber das ist nur der Anzeigename dieses Presets, keine zweite
Fraktion. Die frühere Notiz „alle 5 Zivilisationen" bei der Ladder-Crew-Liste
war ein Zählfehler meinerseits — korrigiert.

Nebenbefund: `dbpremadecivs.dat` hat 21 Einträge und reicht von
„Classical Greece"/„Assyrian Empire"/„Babylon" bis „France"/„Russia"/„United
States"/„China" — passt zu `Starting Epoch=5`/`Ending Epoch=9` in der
Registry. Das Spiel deckt offenbar **drei Epochen** ab (Antike, Mittelalter,
WWII/Modern), nicht nur die im Skirmish gezeigte Antike. Die zuvor als
„Restbestände aus einem anderen Projekt" eingeordneten `Katyusha Rocket
(Russia)`/`Axe Thrower (France)` sind also vermutlich **echter Inhalt einer
anderen Epoche desselben Spiels**, nicht Fremdmaterial — Korrektur zur
vorherigen Einordnung.
* **Chariots** — `Chariot (Rome)`, `Chariot (Egypt) (3P)` — eigenständige
  Kampf-Fahrzeuge, nicht nur Kampagnen-Deko.
* **Sword Banner Soldier** (Egypt/Persian/Rome) — Standartenträger-Einheit.
* **Camel Supply (Rome)** — Nachschub-Einheit.
* **Worker (Greek/Egypt/Persian/Rome)**, `Inf01`-Präfix — **kein** Bug im
  Skript: das ist ein unbenutztes Duplikat, der normale Arbeiter läuft über
  einen separaten `Cit -`-Präfix-Datensatz (`A - Cit - Citizen (Greek)`,
  id-Bereich `Cav00`… anders benannt) und ist längst trainierbar.
* **Nicht empfehlenswert:** 3rd-Person-Helden (Achilles/Cleopatra/Ramses/
  Caesar/Octavian/Alexander/Tiberius/Tor/Aristander/Gladiator) — gehören zum
  Helden-Kameramodus (`3P Hero...`, siehe Milestone-3-Notiz im Java-Projekt),
  vermutlich mit Eindeutigkeits-Annahmen im Code verknüpft; `XXX`-präfigierte
  „TBD"-Gebäude — wörtlich unfertiger Platzhalter; `Prisoner 01/02` —
  unbewaffnete Kampagnen-Deko; `Katyusha Rocket (Russia)`, `Axe Thrower
  (France)` — Russland/Frankreich sind in R&F gar keine Zivilisation, das
  sind Restbestände aus einem anderen Projekt.

### Die eigentliche Bauliste eines Arbeiters — und wie viel davon schon fertig ist

`A - Cit - Citizen (<Civ>)` trägt selbst eine Bauliste mit demselben
`+908`/`+1212`-Mechanismus — das ist vermutlich das Baumenü, das beim
Anklicken eines Arbeiters erscheint (Gebäude *und* direkt bestellbare
Belagerungseinheiten in einer Liste). Für Greek: **53 Einträge**, Egypt 59,
Rome 45, Persian 58. Bereits enthalten, ungepatcht: `Tower Catapult`
(alle 4 Zivilisationen — jede Citizen-Liste referenziert sogar die
*anderer* Zivilisationen mit, vermutlich weil das Feld beim Kopieren der
Vorlage nie bereinigt wurde), `Archimedes Claw` (Greek/Egypt/Rome/Persian —
alle vier!), `Siege Tower` in mehreren Zustanden, `Onager` (Persian direkt,
Building Siege03a), `Fire Raiser` (Greek), `Ballista`, sowie
`Wall Siege Platform` selbst. Auch die Mauer-Kette
(`Wall Plain (MP)` → Bauoption `Wall Siege Platform` → dessen Bauoption
`Tower Catapult`, Schaden 200/1800 HP) und die Trireme-Kette (`Naval Onager`,
350 Schaden, sitzt direkt in der Trireme-eigenen 74-Einträge-Liste) sind
komplett und ohne erkennbare Sperre vorhanden — keine der drei bekannten
"Scenarios"-exklusiven Kennfelder (`-1` bei 144/335/402, siehe
Game-Variant-Abschnitt oben) taucht in diesen Records überhaupt auf.

**Noch nicht geklärt: ob das in einem frischen Skirmish tatsächlich im
Bau-UI auftaucht.** Die Daten sehen vollständig aus; ob es an einer
Zeitalter-/Tech-Voraussetzung hängt, die in einer normalen Partie nie
erreicht wird, oder ob es einfach nie getestet wurde, ist offen — vor
jedem weiteren Patch-Versuch lohnt sich ein Ingame-Check des tatsächlichen
Arbeiter-Baumenüs.

**`Chariot (Greek)` existiert nicht als eigenständiges Objekt.** Einzige
Greek-nahe Streitwagen-Referenz ist `A - Cav00 - Chariot (Hero) (Packed/
Unpack)` — unreferenziert, vermutlich Alexanders persönlicher
Helden-Streitwagen für bestimmte Kampagnenmissionen. Der Szenario-Editor
listet typischerweise *alle* Objekte unabhängig von der gewählten
Zivilisation, das erklärt vermutlich die Beobachtung.

### Bannerträger-Aura — VERALTET, inzwischen gelöst

> Der folgende Absatz ist überholt. Das Feld steht nicht im Objekt-Record, wo
> hier gesucht wurde. Es gibt zwei getrennte Mechanismen: Flächeneffekte über
> `+772`/`+776` und Sonderverhalten über den eingebetteten Block bei `+1044`.
> Siehe die Abschnitte weiter unten. Der Treffer bei `+488` war Zufall.

Dreiwege-Vergleich (Held mit bekannter Aura vs. Bannerträger vs. normale
Truppe/Gebäude ohne Aura) über den kompletten 2012-Byte-Record: genau ein
Feld (`+488`) hat beim Helden einen kleinen, plausiblen Tabellen-Index-Wert
(`5`), während er bei allen anderen `0`/`-1` ist — aber Index 5 in
`dbareaeffect.dat` ist „Helicopter repair", offensichtlich kein
Bronzezeit-Held-Buff. Zufallstreffer, keine echte Spur. Alle anderen
Kandidatenfelder sind entweder immer `0`/`-1` bei allen geprüften Einheiten
oder enthalten offensichtlichen Nicht-Zahlen-Datenmüll (verschobene Strings,
Float-Bitmuster).

**Zwei Erklärungen bleiben:** (a) die Verknüpfung läuft über eine andere
Tabelle, die ich noch nicht identifiziert habe, oder (b) die Aura ist an
die Helden-*Kategorie* im Programmcode hartcodiert, nicht an ein Datenfeld
— dann ließe sie sich nicht per reinem Datenpatch auf den Bannerträger
übertragen. Um das sicher zu beantworten, bräuchte es dieselbe Tiefe wie
damals bei der UI-Hintergrund-Kamera: die ladende Funktion in
`RiseAndFall.exe`/`LowLevelEngine.dll` müsste disassembliert werden, um zu
sehen, wo/ob überhaupt ein Aura-Verweis aus dem Objekt-Record gelesen wird.

**Unklar/nicht verifiziert:** Ob `[3]`/`[4]`/`[41]` wirklich die
UI-Sichtbarkeit steuern oder nur Nebenwirkungen haben, wurde nicht per
Code-Analyse bestätigt, nur per Strukturvergleich mit zwei funktionierenden
Referenzeinheiten — **im Spiel noch nicht getestet** (kein GUI-Zugriff in
dieser Session).

**Für eine künftige Neuimplementierung**: Das Ghidra-Projekt mit vollständiger
Auto-Analyse beider Binaries liegt unter `D:\rnf_re\proj\RNF` (RiseAndFall.exe
und LowLevelEngine.dll importiert, RTTI-Klassennamen aufgelöst) — spart bei
Fortsetzung die ~10 Minuten Analysezeit. Bereits dekompilierte Funktionen
(Pseudo-C) liegen unter `D:\rnf_re\out\*.c`.

### Andere interessante Tabellen (Namen aus Registry/Strings, ungeprüft)

* `db\dbGameVariant.dat` — genau 3 Einträge, in dieser Reihenfolge:
  Index **0 = `Scenarios`**, **1 = `Tournament`**, **2 = `Standard`**
  (feste Satzgröße 332 Byte, Header `u32 count`).

  **Die Variante steht in der Registry** und wird beim Start *gelesen*:
  `HKCU\Software\Midway Home Entertainment\Rise and Fall\Game Options` →
  `Game Variant` (bei diesem Setup `2`, also `Standard`). Verifiziert per
  Disassembly (`RiseAndFall.exe`, Lade-Routine um `0x006e8dd0`): der Wert
  geht über `URegistry::GetRegistryValue` in den Spielzustand nach
  `[esi+0x534]`; existiert der Schlüssel nicht, wird `2` als Default gesetzt
  und geschrieben. Die Speicher-Routine um `0x006e9310` schreibt ihn zurück.
  Ein Kampagnendurchlauf ändert den Wert **nicht** — Kampagnen holen ihre
  Variante offenbar aus der `.scn`-Datei, der Registry-Wert betrifft
  Skirmish.

  Feld-Diff der drei Datensätze (nur abweichende 32-Bit-Felder, Floats
  aufgelöst) — `Scenarios` ist im Wesentlichen „alle Beschränkungen aus":

  | Offset | Scenarios | Tournament | Standard | Deutung |
  |--------|-----------|------------|----------|---------|
  | +120   | **-1**    | 144        | 144      | ID-Referenz, in Scenarios ungesetzt |
  | +128   | **-1**    | 335        | 335      | dito |
  | +280   | **-1**    | 402        | 402      | dito |
  | +292   | **0**     | 500        | 5000     | Einheitenlimit (0 = unbegrenzt; deckt sich mit `Game Unit Limit` in der Registry) |
  | +324   | **0**     | 1          | 1        | Bool-Flag |
  | +208/+212 | 1.0    | 1.0        | 3.0      | Multiplikatoren |
  | +240   | 1.0       | 1.0        | 2.86     | Multiplikator |

  Die drei `-1`-Felder sind die aussichtsreichsten Kandidaten für „welche
  Objekt-/Tech-Beschränkung gilt" — genau das, was Kampagneneinheiten im
  Skirmish sperren würde. **Noch nicht im Spiel getestet.**
* `db\dbcivspecificunitdefines.dat` — klein (13 KB), enthält **keine**
  Fundamente von Javelin/Crane, sondern ~58 generische Gebäude-/Einheiten-
  *Kategorien* (Barracks, Walls, Gates, Fortress, Town Center, …), die pro
  Zivilisation umgeskinnt werden. Kein direkter Baulisten-Schalter.
* `db\dbpremadecivs.dat` — Liste vorgefertigter Zivilisationen für
  Kampagnen/Szenarien (u. a. `"Classical Greece"`, `"Byzantine Rome"`,
  `"Ottoman Empire"` — deutlich mehr als die 4 Skirmish-Standardzivilisationen).
  Denkbarer Ort für eine Kampagnen-exklusive Zivilisation mit erweitertem
  Tech-Tree. **Nicht untersucht.**

## Sonstiges

* `Data/RiseAndFall` — dieselbe Binary wie `RiseAndFall.exe` (10 MB, MZ), mit
  vollständigen C++-RTTI-Namen (`EEDatabase`, `EERandomMap`, …).
* Kommandozeile: `-datapath`, `-redistpath`, `-nodump`, `-loadgame`,
  `-hostgame`, `-joinbyip`, `-playername`, `-scenarioeditor`,
  `-update_saved_games`, `-forceautodetect`.
* `RiseAndFall.sw2` — XML-Hülle mit Base64 (`EncodeMethod="64" Encryp="1"`),
  Softwrap-Lizenzdatei.
* `Data/resource4.dat`, `dfconfig.dfh` — SFFS/Softwrap-Kopierschutz, verschlüsselt.
* `shader.cache` — lesbares Key/Value-Format (`PS_VERSION`=`ps_2_0`,
  `k_MaxBillBoardArraySize`=`236`, …).
* Bilder/Videos liegen offen: `.bmp`, `.dds`, `.ttf`, `.bik` (Bink).

## `.gr2` (Granny3D, RAD Game Tools) — vollständig geknackt, Java-Port existiert

Stand 2026-09-03: Kompletter Java-Reader in `D:\Code\RNFJava\src\main\java\com\rnf\gr2\`
(`Gr2Container`, `Oodle1Decompressor`, `Gr2ElementParser`, `Gr2MeshExtractor`).
Verifiziert an `models\men_ymjavelin_model.gr2`: korrekte Vertex-Anzahl (758),
korrektes Skelett (9 Bones, echte Namen wie „Bip01 Pelvis"), korrekter
Material-Name („Greek Javelin"), korrekte Dreiecks-Indizes (812 Dreiecke).

**Basis:** [opengr2](https://github.com/arves100/opengr2) (MPL-2.0,
Community-Reverse-Engineering, KEIN Wrapper um RADs proprietäres SDK), dessen
Oodle-1-Dekompressor wiederum von
[nwn2mdk](https://github.com/Arbos/nwn2mdk) abgeleitet ist.

**Container** (Header 32 Byte + FileInfo 56 Byte, Format 6, 32-Bit, Little
Endian — das einzige bei uns beobachtete Format):

```
Header:   magic[4×u32] | sizeWithSectors(u32) | format(u32,=0) | extra[8]
FileInfo: format(i32,=6) | totalSize(u32) | crc32(u32) | fileInfoSize(u32,=56)
          | sectorCount(u32) | type{sector,position} | root{sector,position}
          | tag(u32) | extra[16]
Sektor-Tabelle: sectorCount × 44 Byte (compressType, dataOffset, compressedLen,
          decompressLen, alignment, oodleStop0, oodleStop1, fixupOffset,
          fixupSize, marshallOffset, marshallSize — je u32)
```

Sektoren werden dekomprimiert (compressType 0=roh, 2=Oodle-1 — bei unseren
Dateien beobachtet) und zu EINEM flachen Buffer zusammengefügt. Danach werden
**Fixups** angewendet: pro Sektor eine Liste aus (srcOffset, dstSector,
dstOffset)-Tripeln (12 Byte, liegt an `fixupOffset` in der ROHEN, nicht
entpackten Datei) — an Position `sectorOffsets[i]+srcOffset` im flachen
Buffer wird der absolute Offset `sectorOffsets[dstSector]+dstOffset`
eingetragen. Damit werden alle internen "Zeiger" zu simplen Ganzzahl-Offsets
in den flachen Buffer — kein Marshalling/Endian-Swap nötig, da unsere
Dateien bereits Little Endian sind (passend zur Zielplattform).

**Typ-Baum** (selbstbeschreibend, ähnliches Prinzip wie `.udf`/`USTRB`, aber
hier vollständig verstanden dank Referenzcode): Pro Feld ein 32-Byte-Eintrag
`type(u32) | nameOffset(u32) | childrenOffset(u32) | arraySize(i32) | extra[12] | extra4(u32)`,
sequenz-terminiert durch `type=0`. 23 bekannte Typ-IDs (0=NONE bis 22=EMPTYREFERENCE,
siehe `TypeId.java`). Container-Typen (INLINE, REFERENCE*, *ARRAY*) referenzieren
per `childrenOffset` einen weiteren Typ-Baum für ihre Felder; Primitiv-Typen
lesen `arraySize` Werte direkt aus dem Daten-Cursor.

**Eigener Fund, über die Referenzimplementierung hinaus:** Für
`REFERENCE_TO_VARIANT_ARRAY`/`VARIANT_REFERENCE` (Typ 7/5) ist `childrenOffset`
im statischen Schema **immer 0** — das eigentliche Feld-Layout (z. B. pro
Vertex: Position/Normal/UV/BoneWeights/BoneIndices) ist NICHT statisch
bekannt, weil verschiedene Meshes unterschiedliche Vertex-Formate haben
können. Der Typ-Zeiger dafür ist stattdessen das DRITTE gelesene Feld beim
Parsen dieses Knotens (`offset`-Feld in der C-Struktur) — die
Referenzimplementierung (`opengr2`) behandelt dieses Feld fälschlich nur als
Byte-Offset-Addition, nicht als Typ-Zeiger, wodurch bei ihr Vertex-Daten leer
blieben. Mit dieser Korrektur ergeben sich pro Vertex exakt die erwarteten
Felder (`Position` 3×REAL32, `Normal` 3×REAL32, `TextureCoordinates0`
2×REAL32, `BoneWeights` 4×NORMAL_UINT8, `BoneIndices` 4×UINT8).

**Noch offen:** Nur statische Meshes (Bind Pose) werden extrahiert — keine
Skelett-Transformation/Skinning/Animation. `ArtToolInfo.UnitsPerMeter`
(~0,3281 bei unseren Dateien, passend zu „Fuß" als Autorisierungseinheit)
wird zur Skalierung genutzt, aber die genaue Konvention ist nicht durch
Code-Analyse verifiziert, nur empirisch plausibel.

## Grafik / Texturen

Die Engine hat ein echtes VFS. Aus den Symbolnamen in `RiseAndFall.exe`:

```
FSPath::AddDirectory(const FSFileSpec&, bool)
FSPath::AddArchive(FSArchive*, bool)
FSPath::FindFile(const UWideString&, FSFileSpec*&)
FSPath::FindFileInArchive(const UWideString&)
FSPath::GetFileArchiveStatus(const UWideString&, bool&)
GETextureManager::GETextureManager(FSPath*, GEGraphicsQuality)
GETextureManager::SetTexturePath / ReloadTexture / SetTextureQuality
GETexture::GetMipLevelsToDrop
```

**Verifiziert per Dekompilierung** (`FSPath::FindFile`, `LowLevelEngine.dll`
@ 0x1000b2b0, 2026-09-03): Die Funktion durchläuft zuerst alle registrierten
Verzeichnisse (`GetFileAttributesA` pro Verzeichnis+Dateiname) und gibt
**sofort** zurück, sobald eine Datei auf der Platte gefunden wird — die
Archiv-Schleife (`FSArchive::FindFile`) wird dann gar nicht mehr erreicht.
Die Priorität hängt nicht vom `bool`-Parameter an `AddDirectory`/`AddArchive`
ab, sondern rein von der Reihenfolge der zwei Schleifen im Code.
**Lose Dateien überschreiben also garantiert Archivinhalte**, sofern ihr
Verzeichnis bei der `FSPath`-Instanz registriert ist (der Datenpfad `data\`
aus `-datapath "data\"` ist es).

Da lose Dateien über `FSFileSpec::Read` gelesen werden (nicht über
`FSArchive::ReadFATFile`), müssen sie **unverschlüsselt und unkomprimiert**
vorliegen — exakt das, was `tools/rnf_ssa3.pl cat` ausgibt. Ein Override lässt
sich also direkt so erzeugen:

```bash
perl tools/rnf_ssa3.pl cat "Data/data.ssa" "db\dbtechtree.dat" > "Data/db/dbtechtree.dat"
```

Kein Repacken/Wiederverschlüsseln von `data.ssa` nötig, um eine Tabelle zu
ändern — nur die editierte Datei muss am relativen Pfad liegen, unter dem sie
intern referenziert wird (z. B. `db\dbtechtree.dat` → `Data/db/dbtechtree.dat`).
**Die tatsächliche Dateisuche im laufenden Spiel wurde noch nicht getestet**
(kein GUI-Zugriff in dieser Session) — die Aussage stützt sich auf die
Code-Analyse, nicht auf einen Spieltest.

UI-Elemente referenzieren Texturen über logische Namen ohne Endung, z. B.
`textures\UI_xBlueBulletT`, `textures\but_xGamespy_OnlineT` (in `Language.dll`
mitten im Tooltip-Markup).

Lose Grafikdateien im Verzeichnis:

| Datei | Format | Maße |
|-------|--------|------|
| `3DU_yMain_Backdrop.dds` (Wurzel und `Data/Textures/`, identisch) | DXT3, keine Mipmaps | 2048 × 2048 |
| `loadscreen.bmp` | BMP 24 bpp, unkomprimiert | 640 × 480 |
| `html/RiseAndFall_logo.jpg`, `Midway_logo.jpg` | JPEG | Launcher |
| `dfh/*.png`, `*.jpg` | PNG/JPEG | DRM-Loader-Oberfläche |
| `Data/Movies/*.bik` | Bink | Vorschauvideos |

Alle übrigen Texturen liegen in `data.ssa` (v3, verschlüsselt).

## Registry

`HKCU\Software\Midway Home Entertainment\Rise and Fall` — Auflösung und
Grafikoptionen stehen hier, nicht in einer Konfigdatei:

```
Game Window Width  : 1920      AntiAliasing Level : 3
Game Window Height : 1080      Texture Bit Depth  : 32
Custom Refresh Rate: 75        Shadow Quality     : 2
```

Unterschlüssel `Graphics Settings` (Werte 0–3):

```
Flora 3 | Tree 3 | Model 3 | Water 3 | Terrain 3 | Particle 2 | Texture 2
```

`Texture Quality Level` steht auf 2, die meisten anderen auf 3. Zusammen mit
`GETexture::GetMipLevelsToDrop` spricht das dafür, dass aktuell Mip-Stufen
verworfen werden — Obergrenze der Skala aber nicht verifiziert.

## Werkzeuge

* `tools/rnf_ssa.pl` — `list` / `extract` für rass-v1-Archive (Kampagnen).
* `tools/rnf_ssa3.pl` — `list` / `extract` / `cat` für `Data/data.ssa`
  (rass-v3, verschlüsselt). `cat <data.ssa> <interner-Pfad>` gibt eine
  einzelne entpackte Datei auf stdout aus, z. B.:
  `perl tools/rnf_ssa3.pl cat "Data/data.ssa" "db\dbobjects.dat" > dbobjects.dat`.
  Nur Lesen implementiert (kein Repacken/Verschlüsseln der DB-Tabellen).
* `tools/rnf_zl.pl` — `info` / `unpack` / `repack` für `.scn` und `.ees`.
  Round-Trip getestet: alle 9 Blöcke byte-identisch, Größenfeld wird korrigiert.
  **Im Spiel noch nicht gegengetestet** — vor dem Überschreiben Backup anlegen.

### Reverse-Engineering-Umgebung

Für die Analyse von `RiseAndFall.exe`/`LowLevelEngine.dll` installiert unter
`D:\rnf_re\` (bewusst außerhalb dieses Ordners, da Ghidras Windows-Batch-
Skripte mit Leerzeichen im Pfad ("Rise And Fall") nicht zurechtkamen):

```
D:\rnf_re\ghidra\ghidra_12.1.3_PUBLIC\   Ghidra (braucht JDK 21+, NICHT 17)
D:\rnf_re\jdk21_extract\jdk-21.0.12.1+1\ Temurin JDK 21 (für Ghidra)
D:\rnf_re\r2\radare2-6.2.0-w64\bin\radare2.exe   radare2 (schnelle Disassembly ohne Analyse-Wartezeit)
D:\rnf_re\proj\RNF\                      Ghidra-Projekt, beide Binaries bereits importiert + analysiert
D:\rnf_re\scripts\*.java                 Ghidra-Headless-Skripte (Jython wird von Ghidra 12 nicht mehr unterstützt)
D:\rnf_re\out\*.c                        Bereits dekompilierte Funktionen
```

Headless-Dekompilierung eines bekannten Funktionsnamens/Adresse (Beispiel):

```bash
export JAVA_HOME="D:/rnf_re/jdk21_extract/jdk-21.0.12.1+1"
"D:/rnf_re/ghidra/ghidra_12.1.3_PUBLIC/support/analyzeHeadless.bat" \
  "D:/rnf_re/proj" RNF -process "RiseAndFall.exe" -noanalysis \
  -postScript "DumpByAddr.java" -scriptPath "D:/rnf_re/scripts"
```

(Skript nach Bedarf mit neuer Zieladresse anpassen — siehe vorhandene
`DumpOne*.java`/`DumpByAddr*.java` als Vorlage.)

### Wie die Kampagne Klaue/Onager auf Mauern bekommt — geklärt

Direkt aus den Szenariodateien belegt (`Data/Scenarios/*.scn`, entpackt mit
`tools/rnf_zl.pl unpack`):

* `alex 09 blockade.scn` — **91×** „Naval Onager", dazu Trigger wie
  `<P2 Tower Catapults Exists>`, `<P1 Ships in Range of Tower Catapult>`,
  `<P2 Flagship Naval Onager Exists>`.
* `alex 11 tyre3p.scn` — Missionstext im Klartext:
  „The **Archimedes Claws on the Palace walls** will kill the …"
* `alex 10 siege of hali.scn`, `cleo 01 reverse siege.scn` — je mehrfach
  „Tower Catapult".

**Ergebnis: in der Kampagne werden diese Waffen vom Missionsdesigner
*platziert*, nicht gebaut.** Es gibt keinen Bauweg dorthin:

* Kein `Fortress NN (<Civ>)`-Objekt (01–39 pro Zivilisation) hat
  Belagerungsgerät in seiner Bauliste — alle geprüft, null Treffer.
* `A - b  Palace (Persian)` (id 6806) — die „Palace walls" aus Tyre — hat
  eine **leere** Bauliste (Zähler 0).
* `Archimedes Claw` wird in `dbobjects.dat` von genau einem Objekt
  referenziert (`Citizen`), `Naval Onager` ausschließlich von Schiffen
  (Trireme/UberShip).

Die Vermutung „es liegt an einer breiteren Spezialmauer" trifft insofern zu,
dass die Kampagne andere Bauwerke benutzt — aber nicht als *Bauvoraussetzung*:
diese Bauwerke bauen die Waffen ebenfalls nicht, sie tragen nur, was das
Szenario dort hingesetzt hat.

Damit bleibt als einziger bekannter „bauen und montiert aufsitzen"-Mechanismus
im Spiel das Paar **`Wall Siege Platform` → `Tower Catapult`** (bzw. auf
Schiffen `Trireme → Naval Onager`). Ob der Onager diesen Plattform-Mechanismus
mitbenutzen kann, ist **ingame noch offen** — der Plattform-Weg wurde bisher
nicht getestet, da beim Test die Mauer selbst angeklickt wurde.

**Buttons:** `+216` im 232-Byte-`dbButtons.dat`-Satz ist kein Kategorie-, sondern
offenbar ein Slot-Index im Aktionspanel (Gate Left=1, Gate Right=2 direkt
benachbart; Tower Catapult=10, Naval Onager=8). Als Erklärung für fehlende
Sichtbarkeit taugt es nicht — der Onager fehlte im Test schlicht, weil er nur
auf der Plattform stand, nicht an der Mauer. Inzwischen in beiden
(56 Mauer-Records + 14 Plattform-Records).

### Sichtbarkeitsregel im Baumenü — endlich belegt

Für Tech-Einträge der Kategorie **`f1 == 5`** gilt: der Eintrag erscheint im
Baumenü seines Hosts nur, wenn **`field3` UND `field4` beide `-1`** sind.
Sechs Datenpunkte, alle konsistent (Zustand nach den bisherigen Patches):

| Eintrag | f1 | f3/f4 | erscheint |
|---|----|-------|-----------|
| `Ladder (Wall)`            | 5 | `-1`/`-1` | ja  |
| `Naval Onager`             | 5 | `-1`/`-1` | ja  |
| `Tower Catapult` (gepatcht)| 5 | `-1`/`-1` | ja  |
| `Archimedes Claw` (gepatcht)| 5 | `-1`/`-1` | ja |
| `Wall Siege Platform`      | 5 | `-1`/`0`  | **nein** |
| `Wall Siege Platform (Deform)` | 5 | `0`/`0` | **nein** |

`Gate Left/Right` steht mit `0`/`0` sichtbar in derselben Liste, ist aber
Kategorie **`f1 == 4`** und folgt offenbar anderen Regeln — deshalb galt die
Regel zwischenzeitlich als widerlegt. Sie gilt nur innerhalb `f1 == 5`.

Behoben mit `tools/rnf_techvisible.pl` (setzt `f3`/`f4` auf `-1`, aber
ausschließlich bei `f1 == 5`): 8 der 14 `Wall Siege Platform`-Varianten waren
betroffen. **Ägypten und Persien hatten bereits `-1`/`-1`** — dort hätte die
Plattform also von Anfang an gebaut werden können; nur Griechenland und Rom
waren gesperrt.

### Savegames (`.ees`) sind für Objektinspektion (noch) nicht nutzbar

`tools/rnf_zl.pl unpack` öffnet sie problemlos (9 Blöcke), aber die
Objektinstanzen stehen dort weder als Klartextnamen noch als
`dbobjects.dat`-IDs — eine Suche nach allen bekannten IDs ergab nur
Zufallstreffer im Einerbereich, eine Suche nach Namensstrings gar nichts.
Vermutlich werden Objekte über Template-Indizes oder Zeiger referenziert. Für
„welche Mauervariante steht da konkret" wäre also erst das Savegame-Format zu
knacken — deutlich teurer als der direkte Ingame-Test.

### Siege Platform: Datenweg erschöpft — die Entscheidung fällt im Code

Alles Folgende ist gepatcht bzw. geprüft, die Plattform erscheint **weiterhin
nicht** im Mauer-Menü:

* Bauliste aller 56 Mauer-Records enthält sie (Zähler korrekt mitgezogen).
* `field3`/`field4` auf `-1`/`-1` gesetzt (8 von 14 Varianten waren betroffen).
* Gültiger Button vorhanden (`+300` → dbButtons 319, `but_yWallPlatformT`).
* `db\dbupgrade.dat` (69 Sätze à 240 Byte) enthält **keine** der
  Mauer-/Plattform-IDs — die Plattform ist dort also kein Upgrade-Ziel.

**Die `f1==5` → `f3`/`f4 == -1`-Regel ist damit ebenfalls widerlegt.** Sie war
die dritte Datenkorrelation, die sich als Scheinkorrelation entpuppt hat
(nach „`-1` heißt reparbeitet" und „Tech-Baum entscheidet"). Weitere
Feldratespiele sind hier nicht sinnvoll.

**Entscheidender Hinweis vom Nutzer:** Im Szenario-Editor sind Katapult, Klaue
und Onager **frei platzierbar** — auf Mauern, am Boden, in beliebiger
Ausrichtung, ohne Trägerobjekt. Zusammen mit dem Befund, dass die Kampagne sie
ausschließlich platziert (siehe Abschnitt oben), heißt das:
**„auf der Mauer" ist in diesem Spiel eine Position, kein Montage-Verhältnis.**
Ein „bauen → sitzt oben auf" für den Spieler existiert damit möglicherweise
überhaupt nicht als Mechanik; die Kampagne stellt es per Platzierung her.

### RTTI-Walker: von Klassennamen zu echtem Code

`D:\rnf_re\scripts\RttiWalk.java` läuft und liefert reproduzierbar
Klassenname → Type Descriptor → Complete Object Locator → Vtable →
dekompilierte virtuelle Methoden. Ghidras Symboltabelle enthält für dieses
Binary keine demangelten Klassennamen, deshalb ist das der einzige Weg dorthin.

Gefunden: **getrennte Befehlsklassen** `EEMBuildWall` (vtable@`00c4d054`),
`EEMBuildUnit` (`00c4d01c`), `EEMBuildGate` (`00c4cfe4`), dazu `EEABuild`
(`00c4d0b0`). Das Mauer-Menü setzt also je Eintragsart unterschiedliche
Befehle ab — plausibler Ansatzpunkt, warum ein Gebäude-Eintrag anders
behandelt wird als eine Einheit.

Weitere interessante Klassen für spätere Läufe:
`EEAIFOCurrentlyBuildableUnitScreener`, `EECPBuildManager`, `EEUCBuilding`,
`EEUGBuildRepair`, `EEZoneMoraleAreaEffectContainer` (Bannerträger-Aura).

### Logging: kein allgemeines Debug-Log vorhanden

Im Binary existieren nur der Schalter `-nodump` sowie sehr umfangreiche
`OUT OF SYNCH DUMP:`-Ausgaben — das ist ausschließlich
Computerspieler-/Multiplayer-Desync-Zustand (AI-Timer, Angriffsentscheidungen,
Ressourcenzentren). Dazu `saved game conversion.log` und `Totals.log`. Für
Fragen der Art „warum erscheint dieser Baueintrag nicht" gibt es **keinen**
Log-Kanal.

### Konsolidierter Stand der Mauer-Belagerungswaffen

Aufgeräumt nach der Testreihe: die Diagnose-Kontrolleinträge
(`Building Siege…`-Baustellen) wurden aus allen 54 Mauer-Records wieder
entfernt, und die wirkungslose `f3`/`f4`-Änderung an den 8
`Wall Siege Platform`-Einträgen aus dem Original zurückgeholt. Es bleiben nur
Änderungen mit nachgewiesener Wirkung: **838 Bytes** in `dbobjects.dat`,
**70 Bytes** in `dbtechtree.dat`.

Im Mauer-Menü aller vier Zivilisationen jetzt baubar (als Bodeneinheiten,
nicht montiert): **Tower Catapult, Archimedes Claw, Naval Onager**.
`rnf_addbuildable.pl` hat dafür einen `remove`-Modus bekommen.

### Bannerträger-Aura: es gibt kein Aura-Feld an der Einheit

Mit dem RTTI-Walker bis zur Anwendungsfunktion verfolgt
(`EECCApplyAreaEffect::…` = `FUN_00572bd0`):

```c
this = FUN_00bb9ac0( DAT_010215bc[ *(int*)(param_1 + 0x58) ],   // Effekt-Template
                     *(int*)(iVar1 + 0x94),
                     *(int*)(iVar1 + 0x30) + 0x474 );           // Adresse (Position), kein Feldwert
```

Entscheidend: der **Effekt-Index steht auf der Komponente** (`param_1 + 0x58`),
nicht im Einheiten-Datensatz. `DAT_010215bc` ist die geladene
`dbareaeffect.dat`-Tabelle. Der Konstruktor der Komponente
(`FUN_00572ab0`, gefunden über den Vtable-Wert `0x00c57dd4`) initialisiert
`+0x58` **nicht** — das macht der Aufrufer. Direkte Aufrufer des Konstruktors
gibt es **keine**: er wird über eine Factory aufgerufen (Komponentensystem).

**Damit ist erklärt, warum alle Feld-Differenzanalysen an `dbobjects.dat`
ergebnislos blieben: dort gibt es kein Aura-Feld.** Die Aura kommt über eine
angehängte Komponente, wie Helden ihre Fähigkeiten bekommen.

Erfolglos auf der Suche nach der Tabelle, die Komponenten/Fähigkeiten an
Einheiten hängt: `dbcalamity.dat` (147×268, Namen wie „A-Reinvigorate
(Level 1–5)", aber keine konsistente Effekt-Index-Spalte),
`dbspecialunittable.dat` (103×168), `dbcrewedunitdetails.dat` (83×144),
`dbupgrade.dat` (69×240) — alle benutzen offenbar eigene ID-Räume, Suchen nach
bekannten Objekt-IDs ergaben nur Zufallstreffer.

**Konsequenz:** Ein reiner Datenpatch kann dem Bannerträger keine Aura geben.
Das ist der klassische Fall für RafLoader — die Moralberechnung bzw. die
Komponentenerzeugung hooken und die Aura in Lua ergänzen. Gleiche Bauart wie
die noch offene Platzierungslogik.

### `dbcalamity.dat` ist die Komponenten-/Effekt-Tabelle — komplett aufgeschlüsselt

Der Einstieg war die einzige echte Referenz auf den `EECCApplyAreaEffect`-
Konstruktor. Wichtig dabei: eine Suche nach der **absoluten** Adresse im
Binary findet nichts, weil `call` relativ kodiert — man muss Ghidras
Referenzdatenbank fragen (`tools`-Pendant: `D:\rnf_re\scripts\FindRefsTo.java`).

Die referenzierende Funktion `FUN_00571e20` ist eine **datengetriebene
Factory**: sie liest Datensätze zu je `0x10c` = **268 Bytes** aus einer Datei
und erzeugt per `switch` über einen Typ-Code das passende Komponentenobjekt.
268 Byte ist exakt die Satzgröße von `db\dbcalamity.dat` (147 Einträge) —
**diese Tabelle ist also nicht „Katastrophen", sondern das Effekt-/
Komponentensystem des Spiels.**

**Typ-Code steht im Datensatz bei `+132`** (empirisch bestätigt: einzige
Spalte, deren Werte über alle 147 Sätze im Switch-Bereich 0–0x30 liegen, 36
verschiedene Werte).

Alle 35 Komponententypen, aufgelöst über RTTI
(`D:\rnf_re\scripts\NameComponents.java`: Konstruktor → geschriebene Vtable →
COL → Type Descriptor → Klassenname):

| Code | Klasse | Code | Klasse |
|------|--------|------|--------|
| 2 | `EECCEcology` | 0x10 | `EECCContinuousAreaOfEffect` |
| 3 | `EECCEarthquake` | 0x11 | `EECCOneTimeAreaOfEffect` |
| 4 | `EECCHurricane` | 0x12 | `EECCApplyAreaEffect` |
| 5 | `EECCRaiseDead` | 0x13 | `EECCDirectDamage` |
| 6 | `EECCConversion` | 0x21 | `EECCGrapplingHook` |
| 7 | `EECCPlague` | 0xc | `EECCHeroPower` |
| 8 | `EECCLeprosy` | 0xd | `EECCMorale` |
| 9 | `EECCVolcano` | — | `EECCBanzai`, `EECCBlackout`, `EECCBoilingOil`, |
| 10 | `EECCFire` | — | `EECCElephantToss`, `EECCTeleport`, `EECCTimeWarp`, |
| … | | — | `EECCArtilleryBarage`, `EECCRamming`, `EECCNightFall` u. a. |

Praktisch relevant:
* **`EECCMorale` (Typ 13)** und **`EECCContinuousAreaOfEffect` (Typ 16)** sind
  die Bauformen für „Umstehende bekommen einen Bonus" — genau das, was der
  Bannerträger bräuchte.
* **`EECCGrapplingHook` (Typ 33)** ist die Archimedes-Klaue: Einträge
  `[112] A-GrapplingHook` und `[114] A-GrapplingHook (Sailor version)`.
* Die antiken Heldenfähigkeiten sind Typ 12: `A-Reinvigorate`, `A-Panic`,
  `A-Invulnerabilty`, `A-Persuasion`, `A-Artillery Spotter`, `A-Charge`
  (jeweils Level 1–5). Präfix `A-` = Antike, `Q-` = spätere Epoche.
* Einziger antiker Dauer-Flächeneffekt: `[116] A-Sirocco` (Typ 16).

**Nachtrag: die Aura läuft NICHT über dbcalamity.** Die Zuordnung steht direkt
im Objekt-Record - siehe den nächsten Abschnitt. `dbcalamity` ist das System für
aktive Fähigkeiten (Heldenkräfte, Katastrophen), nicht für passive Auren.

### Passive Auren: `dbobjects` +772 / +776 -> `dbareaeffect`

**Ein Objekt hat zwei Flächeneffekt-Slots, bei `+772` und `+776`**, je ein
Index in `db\dbareaeffect.dat`. `0` ("None (don't delete!!!!)") und `-1`
bedeuten beide "keiner".

Gefunden über die Laufzeitseite statt durch Raten im Record: die einzige Stelle,
die die Effekt-Tabelle indiziert, ist

```c
// FUN_00a1c4e0 - Radius-Check gegen einen Flächeneffekt
local_34 = *(int **)(*(int *)(DAT_010215bc + *(int *)(*(int *)(iVar10 + 0x90) + 0x390) * 4) + 0x24);
local_30 = (float)local_34 * (float)local_34;   // Radius quadriert fuer den Distanzvergleich
```

`unit + 0x90` ist das Laufzeit-Template, `template + 0x390` der Effektindex.
Der Template-Konstruktor `FUN_00a1dd00` zeigt, woher der Wert stammt:

```c
*(undefined4 *)(param_1 + 0x390) = *(undefined4 *)(param_3 + 0x308);   // 0x308 = 776
```

**Laufzeit-Offsets sind also NICHT gleich Datei-Offsets** - dass beim Bauliste
0x38C/0x4BC zufällig auf 908/1212 passten, hat mich hier fast in die Irre
geführt. Erst diese Zuweisung liefert die Übersetzung.

Wer in R&F wirklich einen Flächeneffekt hat (Gegenprobe über alle 3079 Records):
Town Center -> `A Taxation Town Center`, Government Center -> `A Taxation
Government Center`, Town Defense und Recruitment Center -> `A Angry Tether` +
`A Defender Range`, und - der wichtige Fall - **`A - Inf00 - Alexander Melee -
3rd Person (Greek)` -> `A Hero Attention`. Eine Einheit. Damit ist belegt, dass
der Slot auch an Einheiten funktioniert und nicht nur an Gebäuden.**

### `dbareaeffect.dat`: 79 Records à 200 Byte

| Offset | Bedeutung |
|--------|-----------|
| +0 | Name, NUL-terminiert (bis +99) |
| +104 | eigener Index |
| +108 | Effekttyp: 1 Heilung, 2/5/6 Moral, 3 Tempel, 4 Universität, 7 Wirtschaft, 8/12/13 Tarnung, 9 Nachschub, 14 Tempo, 15 Steuern, 16 Hero Attention, 17 Angry Tether, 18 Defender Range |
| +112 | 1 = wirkt auf Gebäude/sich selbst, 2 = wirkt auf Einheiten |
| +156 | **Radius in Metern, float** |
| +164 | **Wirkungsstärke, float** |
| +168, +172 | zweite und dritte Stärke (nur die Moral-Typen setzen alle drei) |

Radius und Stärke sind nicht geraten, sondern aus den Daten belegt: jeder
`… Rng N`-Eintrag hat bei +156 exakt `N.0f`, und bei den Typen, die nur eine
Zahl brauchen, steht sie allein bei +164 - `Q Drummer Boy Speed` hat dort
`1.5`, `A Taxation` hat `3.0`, alle Heilungen `0.98`, während +168/+172 `0`
bleiben. Die Moral-Typen setzen alle drei auf `1.0`, also neutral: Moral ist
ein dreiteiliger Bonus, den die Designer nie scharf gestellt haben.

Viel von der Tabelle ist totes Empire-Earth-Erbe (Präfix `Q`, plus Tarnung,
Tempel, Universität); die in R&F benutzten Einträge tragen den Präfix `A `.
Der Code für die alten Typen ist aber noch da - nur die Daten zeigen nirgends
mehr hin.

### `dbspecialunittable.dat` und der eingebettete Block bei `dbobjects` +1044

**103 Records à 168 Byte.** Das ist die Tabelle, die einem Objekt sein
Engine-Sonderverhalten gibt: `A-Climbable`, `A-Generic Mountable`,
`A-Siege Platform`, `A-Military Trainer`, `A-Greek Walls`, `A-Prison`,
`A-Resurrection`, `A-Chariot`, `A-Town Defense` und so weiter.

Der Clou: **`dbobjects` +1044…+1211 ist eine byteweise identische Kopie eines
dieser Records.** 1044 + 168 = 1212, also genau bis zum Beginn der Bauliste.
Belegt durch direkten Vergleich: der Block des `Military Trainer` stimmt auf
alle 168 Bytes mit `dbspecialunittable[52]` überein, der von normaler
Infanterie mit `[0] None`.

Innerhalb des Blocks (Record-relativ in Klammern):

| Block | Record | Bedeutung |
|-------|--------|-----------|
| +0 | +1044 | Name des Verhaltens, NUL-terminiert |
| +100 | +1144 | Typcode des Verhaltens |
| +104 | +1148 | Index in `dbspecialunittable` |
| ab +108 | ab +1152 | Parameter des Verhaltens |

Für `A-Military Trainer`: +108 = `0.05f` (Rate), **+112 = `3.0f` (Radius in
Metern)**, +120 = 10, +124 = 20.

Praktische Folge: weil der Block *pro Objekt* eingebettet ist, kann man einem
einzelnen Objekt ein abgewandeltes Verhalten geben, ohne die globale Tabelle
und damit alle anderen Nutzer zu verändern. Genau so bekommt der Bannerträger
den Trainer-Effekt mit Radius 10, während der echte Military Trainer bei 3
bleibt. (Ungeprüft ist, ob die Engine wirklich die eingebettete Kopie liest
oder doch über `+1148` in die globale Tabelle geht - falls der größere Radius
ohne Wirkung bleibt, ist das die Erklärung.)

Bemerkenswert: **`A-Siege Platform` (Index 49) wird von keinem einzigen der
3079 Objekte benutzt.** Das Verhalten existiert, ist aber nie verdrahtet
worden. `A - b  Wall Siege Platform` ist entgegen dem Namen keine Waffe,
sondern eine **Mauer-Variante** mit ganz normalem `A-Greek Walls`-Verhalten.

### Warum `Wall Siege Platform` nie im Mauer-Menü auftauchte

Nicht, weil es fehlte - es steht im **Originaldatenstand** als *erster*
Eintrag der Bauliste jeder Mauer. Die Ursache liegt in `dbButtons.dat` bei
`+216`:

**`+216` ist der feste Platz im Aktionsmenü. `0` heißt „nimm die nächste freie
Zelle", jeder andere Wert nagelt den Button auf genau diese Zelle.** Die
Verteilung stützt das: 2578 der 2921 Buttons stehen auf 0.

Im Mauer-Menü stehen damit gleichzeitig:

| Eintrag | Button | Platz |
|---------|--------|-------|
| Ladder (Wall) | 410 | 0 (automatisch) |
| Gate Left | 17 | 1 |
| **Gate Right** | 18 | **2** |
| **Wall Siege Platform** | 319 | **2** — Kollision |

Zwei fest verdrahtete Buttons auf derselben Zelle, und das Tor gewinnt. Deshalb
war die Plattform unsichtbar, obwohl Bauliste, Objekt und Button alle in
Ordnung waren. Behoben, indem die acht Plattform-Buttons (318–321, 558,
563–565) auf 0 gesetzt wurden. Das erklärt rückblickend auch, warum beim
Hinzufügen der Belagerungswaffen mal die eine, mal die andere sichtbar war.

**Damit ist die frühere Notiz „Datenweg erschöpft" widerlegt** - der Fehler war,
nur in Objekt- und Techtree-Records zu suchen und die UI-Tabelle nicht als
Filter in Betracht zu ziehen.

### Das Aktionsmenü: `dbButtons` +216 ist ein Platz, aber nur 0-13 sind sicher

Zwei Korrekturen an früheren Fehlannahmen in diesem Abschnitt.

**`0` bedeutet nicht „automatisch einsortieren", `0` ist Platz 0.** Deshalb
stapelt sich dort alles ohne eigenen Platz - sichtbar nur, wenn mehr als ein
solcher Eintrag gerade *verfügbar* ist. Nicht verfügbare Einträge (etwa die
Dutzenden Einheiten anderer Zivilisationen in jeder Kaserne) zeichnen nicht mit.

**Die Plätze sind ein 0-basierter Index auf die Controls `SRMTrain/Research
Button N+1`** aus `Data/ui/main game form.xml` (dort `Value` = 700 + N).
Deren Geometrie steht im Formular:

| Button | Plätze | Position |
|--------|--------|----------|
| 1-7 | 0-6 | y=1028, x=630..1094 - obere Reihe der Kommandoleiste |
| 8-14 | 7-13 | y=1102, x=630..1094 - untere Reihe |
| 15-42 | 14-41 | y=257 bzw. 193, x=382..1214, anderer Spaltenabstand - ein **anderer Bildschirmbereich** |

Daraus folgt die Spaltenregel: **Platz N und Platz N+7 liegen direkt
übereinander.** Das erklärt den Bannerträger-Bug exakt - er stand auf Platz 0
(Button 1) und damit senkrecht über dem Schwertkämpfer auf Platz 7 (Button 8),
genau dort, wo dessen Aufwertungs-Icon sitzt.

**Plätze ab 14 sind unberechenbar.** Sie landen im oberen Block, und ein dort
abgelegter Eintrag hat in einem Test einen Eintrag der unteren Leiste verdrängt
(Spikes auf 16 statt des Settlements auf 7). Der Originaldatenstand benutzt
zwar Werte bis 38, aber fast nur an Objekten, die im Skirmish nie erscheinen.
**Für eigene Einträge nur 0-13 vergeben.**

Ein Platz muss in **jedem** Menü frei sein, in dem der Button vorkommt: die
Belagerungswaffen stehen in der Mauer- *und* der Arbeiter-Bauliste. Und ein
Button gehört oft mehreren Objekten - `btn 322` etwa den Mauer-Ecken *aller*
Zivilisationen und den Palisaden-Morph-Varianten. `tools/rnf_menu.pl` zeigt ein
Menü so, wie das Spiel es auslegt, und macht Kollisionen vor dem Patchen
sichtbar.

Wichtige Einschränkung: unter den 14 Plätzen der Kommandoleiste ist in keinem
der vier Arbeiter-Menüs derselbe Platz frei. Ein Objekt, das alle vier
Zivilisationen teilen (Palisade: ein Objekt, ein Button), lässt sich darum
ohne Umbau gar nicht unterbringen; Objekte mit civ-eigenem Button (Holzturm,
Archimedes-Klaue) schon, mit je civ-eigenem Platz.

### Der Trainer-Effekt

`A-Military Trainer` (`dbspecialunittable` 52) hängt an genau zwei Objekten:
`A - Inf02 - Military Trainer (Greek)` und `A - Inf01 - Greek General (Greek)`.
Im Spiel sichtbar daran, dass das Banner der trainierten Gruppe kurz rot
aufleuchtet.

Parameter im eingebetteten Block (Record-Offsets in Klammern):
`+108 (+1152)` = `0.05f` - das sind die +5 % des Spiels,
`+112 (+1156)` = `3.0f` Radius in Metern, `+120 (+1164)` = 10,
`+124 (+1168)` = 20 (Bedeutung noch offen, plausibel Dauer und Obergrenze).

**Belegt, dass die Engine die objekteigene Kopie benutzt** und nicht über den
Index in die globale Tabelle geht - der Template-Konstruktor `FUN_00a1dd00`
kopiert sie explizit:

```c
if (*(int *)(param_3 + 0x47c) < 1) {          // 0x47c = 1148, der Index
    *(undefined4 *)(param_1 + 300) = 0;        // Index 0 -> gar kein Verhalten
} else {
    puVar11 = operator_new(0xa8);              // 168 Byte
    puVar13 = param_3 + 0x414;                 // 0x414 = 1044, der Block
    for (iVar9 = 0x2a; iVar9 != 0; iVar9--) { *puVar14++ = *puVar13++; }
    *(undefined4 **)(param_1 + 300) = puVar14; // Template+0x12c
}
```

Ein einzelnes Objekt kann darum eine abgewandelte Fassung bekommen, ohne alle
anderen Nutzer desselben Verhaltens zu verändern.

### `dbobjects` +368…+404: die Voraussetzungsliste — und der „Aus"-Schalter

Zehn aufeinanderfolgende int32-Felder ab `+368`. `-1` heißt „keine
Voraussetzung"; Gebäude tragen zusätzlich `1076` bei `+376`, Einheiten echte
IDs (der Bannerträger `1700` bei +368 und `1770` bei +384, der Greek General
`1700`/`1703`/`1744`).

**Objekte, die im Skirmish nie erscheinen sollen, haben hier `0` bei +368 und
neunmal `100000`** — eine ID, die es nicht gibt, also eine Bedingung, die nie
erfüllt werden kann. Gefunden bei `Tower Timber (SP)`, `Wall Palisade (SP)` und
`Wall Spikes (SP)`, alle drei Szenario-Objekte.

Das war die Erklärung für einen hartnäckigen Fehlschlag: die Objekte in die
Arbeiter-Bauliste einzutragen, ihnen einen freien Menüplatz und einen Preis zu
geben genügt **nicht** — sie blieben unsichtbar, weil die Voraussetzung nie
erfüllbar war. Bauliste, Button-Platz und Techtree-Eintrag sind notwendig, aber
dieser Block ist die eigentliche Freigabe.

Zum Freischalten das Muster eines funktionierenden Gebäudes übernehmen:
`+368=-1, +372=-1, +376=1076, +380…+404=-1`.

Gegenprobe, die zugleich eine andere Vermutung ausräumt: **`Wall Siege
Platform` steht hier auf `-1`/`1076`, ist also *nicht* auf diesem Weg gesperrt.**
Deren Unsichtbarkeit hat eine andere Ursache und ist weiter offen.

### Nachtrag zum Arbeitermenü

`db\dbcivspecificunitdefines.dat` (60 Records à 216 Byte) ist eine
**Kategorie → Zivilisation**-Zuordnung, keine Menüdefinition: `+124` Griechen,
`+132` Perser, `+140` Rom, `+188` Ägypten, jeweils ein *Record-Index* in
`dbobjects`. Eindeutig ablesbar an Record 43 (Barracks MP aller vier), 54
(Wall Plain aller vier), 16 (Tower 1x1 aller vier). Die Spalten `+148…+180`
sind Empire-Earth-Erbe (dort stehen noch UK-/Persien-Marktbuden).

Das Arbeitermenü kommt trotzdem aus der Bauliste des Citizen-Objekts - der
Beweis ist der Voraussetzungsblock oben: dieselben Baulisteneinträge werden
sichtbar, sobald `+368…+404` freigegeben ist.

### Spielerfarbe: der Alphakanal der Textur — und warum manche Einheiten braun bleiben

Der Spielerfarb-Kanal einer Einheitentextur steckt im **Alpha**. Eine Textur im
Format **DXT1 hat gar keinen Alphakanal** und kann die Maske darum nicht
tragen; die Einheit erscheint in ihrer Grundfarbe (bei den Kampagneneinheiten
braun) und bleibt bei jedem Spieler gleich.

Gemessen an den `.dds`-Dateien im Archiv:

| Textur | Format | Teamfarbe |
|--------|--------|-----------|
| `men_yMinfantry_L1_02t` (normaler Schwertkämpfer) | DXT3 | ja |
| `men_yMspartan_t` (Spartaner) | DXT3 | ja |
| `men_yMflagbearer_02t` (Bannerträger) | **DXT1** | **nein** |
| `men_yMjavelin_t` (Speerwerfer) | **DXT1** | **nein** |

Reparabel wäre das durch Umwandeln nach DXT3 plus einer von Hand gesetzten
Alphamaske - also echte Grafikarbeit, kein Datenpatch.

### Objekt → Grafik: `dbobjects` +304 → `dbgraphics.dat`

`db\dbgraphics.dat`: 2477 Records à 212 Byte. `+0` Name, **`+100` Modellname**,
`+204` eigener Index. **`dbobjects` +304 ist der Index in diese Tabelle**
(gefunden, indem für jedes Objekt das Feld gesucht wurde, dessen Wert dem
`dbgraphics`-Index gleichen Namens entspricht - 1295 Treffer bei +304, sonst
keine).

Zwei Beobachtungen aus dem Spiel damit erklärt:

* **Alle vier Bannerträger benutzen dasselbe Modell `men_yMflagbearer_02`.**
  Sie haben zwar je einen eigenen `dbgraphics`-Eintrag (1867/147/132/115), aber
  alle vier tragen denselben Modellnamen. Im ganzen Archiv existiert nur dieses
  eine Fahnenträger-Modell - das griechische Banner ist im Asset gebacken und
  ohne neue Grafik nicht zu ändern.
* **`Archer (Chariot) (Rome)` zeigt auf denselben Grafik-Eintrag 60 wie die
  ägyptische Fassung**, und `Cav03b - Chariot (Rome)` auf 630
  (`cav_yEchariotarcher`). Im Grafikbestand gibt es überhaupt nur zwei
  Streitwagen: den ägyptischen und den persischen Sichelwagen. Einen römischen
  hat das Spiel nie gehabt.

### `dbtechtree` [29] ist die UI-Klasse

Verteilung über alle Trainingseinträge: `2` = vom Arbeiter baubare Gebäude
(138 Stück), `4` = Bürger/Tiere/Town Defense, `5` = Infanterie, `6` = Bogen,
`7` = Kavallerie, `8` = Marine, `9` = Tore und Mauern, `10` = Turm-Aufwertung,
`11` = Streitwagen-/Elefanten-Bogen, `-1`/`0` = keine Klasse.

**Jedes Gebäude, das im Arbeitermenü erscheint, hat hier `2`.** Holzturm (`-1`)
und Palisade (`0`) standen in gar keiner Klasse - das ist neben dem
Voraussetzungsblock bei +368 die zweite Sperre, die sie unsichtbar hielt.

---

## Arbeitsregeln und gesicherter Stand — Sitzung 2026-09-05

Dieser Abschnitt ist die Kurzfassung für den Einstieg in die nächste Sitzung.
**Vor dem nächsten Patch lesen.** Er hält vor allem fest, was *nicht*
funktioniert, damit es nicht noch einmal probiert wird.

### Was heute im Spiel bestätigt wurde

* **Kasernenmenü Griechen ist in Ordnung.** Der Bannerträger auf Platz 11
  verdeckt das Schwert-Upgrade nicht mehr. Die Diagnose stimmte: er stand auf
  Platz 0 und damit senkrecht über dem Schwertkämpfer auf Platz 7.
* Bannerträger sind in allen vier Kasernen ausbildbar, der Greek General in der
  Spartaner-Akademie.
* **Holzturm und Palisade erscheinen weiterhin nicht.** Zwei Sperren wurden
  nacheinander gefunden und beseitigt (Voraussetzungsblock +368, UI-Klasse
  `t[29]`); ob das jetzt reicht, ist **ungetestet**.
* Die Belagerungsplattform erscheint weiterhin nicht.

### Harte Regeln für Menü-Patches

1. **Menüposition ist nicht allein `dbButtons +216`.** Gegenbeweis: in der
   römischen Kaserne stehen Bogen- *und* Schwertkämpfer aller Stufen auf Platz
   7, und das Spiel zeigt sie trotzdem getrennt. Der Wert ist notwendig, aber
   die Engine zieht noch etwas anderes heran (vermutlich die UI-Klasse
   `dbtechtree[29]`, die Rom/Griechen `5` und Ägypten/Persien `6` gibt).
   **Solange das nicht verstanden ist: einen neuen Eintrag nur auf einen Platz
   legen, der in *diesem* Menü in keiner Zeile vorkommt, und danach im Spiel
   prüfen.**
2. **Nur Plätze 0–13 vergeben.** 0–6 ist die obere, 7–13 die untere Reihe der
   Kommandoleiste (`SRMTrain/Research Button 1–14` in `Data/ui/main game
   form.xml`, y=1028 bzw. 1102). Platz N und N+7 liegen senkrecht übereinander;
   die obere Reihe trägt die Aufwertungen der Einheit darunter. Ab 14 landet
   der Eintrag in einem anderen Bildschirmbereich - dort verschwand das
   Settlement, als die Spikes auf 16 lagen.
3. **Ein Button gehört oft mehreren Objekten.** `btn 322` = Mauer-Ecken aller
   Zivilisationen *und* Palisaden-Morph; `btn 47` = alle drei Kolosseen.
   Vor jeder Verlegung prüfen, wer den Button sonst noch benutzt.
4. **Ein Platz muss in jedem Menü frei sein, in dem der Button vorkommt.**
   Belagerungswaffen stehen in der Mauer- *und* der Arbeiterliste.
5. **Mehrfachbelegung ist im Originalstand normal** (SP- und MP-Variante
   desselben Gebäudes teilen sich einen Platz, weil nie beide gleichzeitig
   verfügbar sind). Ein Problem ist nur, wenn zwei *gleichzeitig verfügbare*
   Einträge kollidieren.

### Was ein Objekt braucht, um überhaupt baubar zu sein

Alle vier Punkte sind nötig; jeder einzelne genügt nicht:

1. Eintrag in der Bauliste des Erzeugers (`+908` Zähler, `+1212` Einträge —
   immer `tools/rnf_buildlist.pl` benutzen, das hält beide synchron).
2. Ein Techtree-Trainingseintrag mit Zeit `[7]` und Kosten `[10]`.
3. **`dbtechtree[29]` = passende UI-Klasse** (2 = vom Arbeiter baubares Gebäude,
   5 Infanterie, 6 Bogen, 7 Kavallerie, 8 Marine, 9 Tore/Mauern, 11 Streitwagen).
   `-1` oder `0` heißt „keine Klasse" und macht den Eintrag unsichtbar.
4. **`dbobjects +368…+404` freigegeben.** `-1` überall, Gebäude zusätzlich
   `1076` bei `+376`. Der Wert `100000` in diesen Feldern ist eine
   Voraussetzung, die es nicht gibt — der Aus-Schalter für Szenario-Objekte.

### Endgültig geklärt — nicht noch einmal versuchen

* **Bannerträger tragen bei jeder Zivilisation das griechische Banner.**
  Im ganzen Archiv existiert nur ein Fahnenträger-Modell
  (`men_yMflagbearer_02`). Alle vier `dbgraphics`-Einträge zeigen darauf.
  **Ohne neue Grafik nicht lösbar.**
* **Es gibt keinen römischen Streitwagen.** Im Grafikbestand nur
  `cav_yEchariotarcher` (ägyptisch) und `cav_yPscythechariot` (persisch).
  `Archer (Chariot) (Rome)` zeigt schon im Originalstand auf den ägyptischen
  Eintrag 60. Kein Patchfehler, ein nie fertiggestelltes Objekt.
* **Bannerträger und Speerwerfer nehmen keine Teamfarbe an, weil ihre Textur
  DXT1 ist** — ein Format ohne Alphakanal, und im Alpha steckt die
  Spielerfarb-Maske. Schwertkämpfer und Spartaner sind DXT3. Nur durch
  Umwandeln nach DXT3 plus gemalter Maske zu beheben, also Grafikarbeit.
* **Spikes (`Wall Spikes`) kann ein Arbeiter nicht bauen**: Familie 35 =
  „Ambient", also Deko statt Gebäude. Menüplatz ändert daran nichts.
* **Die Aura läuft nicht über `dbcalamity`** (das ist das System für aktive
  Fähigkeiten), sondern über zwei getrennte Wege: Flächeneffekte via
  `dbobjects +772/+776` → `dbareaeffect`, und Sonderverhalten via den
  eingebetteten 168-Byte-Block bei `dbobjects +1044`.
* **`dbcivspecificunitdefines.dat` ist nicht die Menüquelle**, sondern eine
  Kategorie→Zivilisation-Zuordnung (+124 Griechen, +132 Perser, +140 Rom,
  +188 Ägypten, jeweils ein *Record-Index* in `dbobjects`).
* **`dbtechtree[30]` (String-ID) entscheidet nicht über Sichtbarkeit** — der
  Bannerträger funktioniert mit `-1`.
* Ältere widerlegte Theorien stehen weiter oben im Dokument (f3/f4 = -1,
  „Techtree entscheidet Sichtbarkeit", „f1==5 braucht -1/-1").

### Offene Punkte für die nächste Sitzung

1. Holzturm und Palisade nach den beiden Freigaben im Spiel prüfen.
2. Bannerträger in der römischen Kaserne: stand auf 0 (Konflikt mit dem
   Schwert-Upgrade), dann 11 (Konflikt mit dem Zenturio-Feld), dann 9
   (Konflikt mit dem Bogenschützen), jetzt **10 — ungetestet**. Falls es
   wieder kollidiert, ist die Platzlogik ohne Code-Analyse nicht zu knacken;
   dann `SRMTrain/Research`-Auswertung in Ghidra aufmachen.
3. Belagerungsplattform: Voraussetzungsblock und UI-Klasse sind in Ordnung
   (`-1/1076`, `t[29]=9` wie die Tore). Ursache weiterhin unbekannt. Verdacht:
   4x4-Grundfläche (`+408`) mit Mauer-Verhalten, was die Mauer-Ziehlogik nicht
   platzieren kann.
4. Trainer-Effekt: Dauer und Persistenz des Bonus sind ungeklärt
   (Blockfelder `+120`/`+124` = 10 und 20, Bedeutung unbelegt).
5. Texturarbeit (DXT1→DXT3 mit Alphamaske) nur nach Rücksprache — das ist
   Geschmacksfrage, welche Flächen Teamfarbe tragen sollen.

### Menü-Platzlogik: was der Code sagt (Sitzung 2026-09-06)

Der Gegentest hat mein Zellenmodell widerlegt: **ein Stall — ein Objekt, von
dem sicher ist, dass es baubar ist und im Menü erscheint — verschwindet
vollständig, wenn man nur seinen `dbButtons +216` von 10 auf 6 ändert.** Nicht
verschoben, weg. Gleichzeitig reagiert die *Kaserne* sauber auf dieselben Werte
(Bannerträger 0 → 11 → 9 → 10 → 12 mit jeweils nachvollziehbarer Wirkung).
Baumenü der Arbeiter und Trainingsmenü der Gebäude verhalten sich also
unterschiedlich.

Aus dem Code gesichert:

* **Die Engine klemmt den Platz hart auf 0…13**, an zwei Stellen mit derselben
  Formel (`FUN_008e5550` beim Aufbau eines Panel-Eintrags, `FUN_008d7120` beim
  Platzieren):

  ```c
  iVar9 = *(int *)(*(int *)(param_1 + 8) + 0xf0);
  if ((iVar9 < 0) || (0xd < iVar9)) { iVar9 = iVar9 / 1000 + -1; }
  ```

  Damit ist die Regel „nur 0–13 vergeben" nicht mehr Erfahrung, sondern belegt.

* **`template + 0xf0` stammt aus `dbobjects + 392`** (`FUN_00a1dd00`:
  `*(param_1 + 0xf0) = *(param_3 + 0x188)`, 0x188 = 392).

* **`+392` ist bei *jedem* normal baubaren Objekt `-1`** — Stall, Hafen,
  Siedlung, Turm, Kaserne, Schwertkämpfer, Zenturio, Spartaner, alle. Nur die
  gesperrten Szenario-Objekte (Holzturm, Palisade) trugen dort **`100000`**,
  was die Formel in **99** verwandelt, also außerhalb 0–13.
  `-1` ist der Normalfall, `100000` ein bewusster „nie"-Marker.

* Der Platz wird über eine Map nachgeschlagen (`FUN_008deef0` → `FUN_008dde40`,
  Schlüssel ist genau dieser Wert). Kollisionen sind also nicht „zwei Icons
  übereinander", sondern ein Map-Treffer, der den einen Eintrag ersetzt.

**Achtung, eigener Fehler:** Der Block `+368…+404` wurde am 05.09. pauschal auf
`-1` gesetzt, ohne die Einzelbedeutung zu kennen. `+392` gehört dazu und hat
eine eigene Funktion. Der gesetzte Wert war zufällig der richtige (`-1`), aber
**in diesem Block nie wieder pauschal schreiben** — Feld für Feld prüfen.

**Noch offen:** Warum der Stall auf Platz 6 verschwindet, obwohl Rom dort sein
Kolosseum stehen hat. Es sind mindestens zwei Felder beteiligt (`dbButtons
+216` und `dbobjects +392`); die vollständige Auswertung liegt in
`FUN_008d7120` (Platzierung) und `FUN_008e5550` (Eintragsaufbau) — dort
weitermachen, nicht wieder im Menü raten.

### Code-Analyse Menüplatz — Zwischenstand 2026-09-06

Gesichert:

* **Die 0…13-Klemmung steht an drei Stellen im Binary** (`FUN_008e5550`,
  `FUN_008d7120`, `FUN_00b71fe0`), jedes Mal identisch:
  `if ((v < 0) || (0xd < v)) v = v / 1000 - 1;`. Die Regel „nur 0–13" ist damit
  bewiesen.
* **`dbobjects +392` ist ein reiner Ein/Aus-Schalter, kein Platz.** Über alle
  3079 Objekte kommen nur zwei Werte vor: `-1` (636 Objekte, passiert die
  Klemmung unverändert) und `100000` (2443 Objekte, wird zu 99 und fällt
  heraus). Nie ein Wert zwischen 0 und 13.
* `dbobjects +392/+396/+400` → Template `+0xf0/+0xf4/+0xf8`
  (`FUN_00a1dd00`, Quelle `param_3 + 0x188/0x18c/400`).
  **`+396` ist ein zweiter Button-Index**: `item+8 = ButtonTabelle[+396]`
  (`FUN_0056fc20`). Bei normalen Objekten sind alle drei `-1`.
* Der Platz wird über eine Map nachgeschlagen (`FUN_008deef0`), nicht über ein
  Array — eine Kollision *ersetzt* den Eintrag, sie zeichnet ihn nicht nur zu.
  Das deckt sich damit, dass der Stall komplett verschwand.
* `template+0xfc` (das Feld, das in `FUN_0056fc20` nach `item+0x28` geht) wird
  **aus dem Objektnamen berechnet** (`FUN_00a04110`), ist also kein Datenfeld.

**Nicht gefunden:** die Stelle, die `dbButtons +216` in eine Bildschirmposition
umsetzt. Alle Spuren dorthin endeten in generischen Hilfsfunktionen oder in
Zufallstreffern (701 und 110/123 sind an den gefundenen Stellen Sound- bzw.
Grafik-IDs).

**Stärkste offene Beobachtung:** Im griechischen Arbeitermenü funktionieren
ausschließlich die Zellen, die der Originaldatenstand dort schon benutzt
(1, 2, 4, 7, 8, 9, 10, 11, 13). Alles auf 3, 6 oder 12 verschwindet — auch ein
Stall, von dem sicher ist, dass er baubar ist. Bei Ägypten sind 3 und 5
original und funktionieren, bei Rom die 6. Ob daraus folgt „eine Zelle rendert
nur, wenn diese Zivilisation sie im Original schon benutzt", ist die nächste zu
prüfende Frage — dafür fehlt eine Aufzählung des Arbeitermenüs aus dem Spiel,
so wie sie für die römische Kaserne den Durchbruch brachte.

**Keine freie Zelle im griechischen Arbeitermenü:** 4 trägt Markt, Basar und
den aufgewerteten Turm; 13 den Fire Raiser. Ein neuer Eintrag müsste dort etwas
verdrängen — deshalb vorerst nicht angefasst.

### Arbeitermenü: Ist-Zustand aus dem Spiel (Griechen) und was daraus folgt

Aufzählung aus dem Spiel, 7 Spalten x 2 Reihen:

```
Reihe 1:  Settlement  Tower  Hafen  Stall   —      —      Katapult
Reihe 2:  Basar       Mauer  Kaserne Statue Akademie —     Fire Raiser
```

Gegenüberstellung mit `dbButtons +216` (Position = links oben 0, dann
fortlaufend bis 13):

| Position | angezeigt | `+216` laut Daten | passt |
|---|---|---|---|
| 0 | Settlement | 7 | nein |
| 1 | Tower 1x1 | 1 | **ja** |
| 2 | Hafen | 2 | **ja** |
| 3 | Stall | 10 | nein |
| 4 | leer | Basar/Markt/Turm-Upgrade liegen auf 4 | nein |
| 5 | leer | Archimedes-Klaue liegt auf 5 | nein |
| 6 | Katapult | nichts liegt auf 6 | nein |
| 7 | Basar | 4 | nein |
| 8 | Mauer | 8 | **ja** |
| 9 | Kaserne | 9 | **ja** |
| 10 | Statue | 11 | nein |
| 11 | Akademie | 11 | **ja** |
| 12 | leer | Belagerungsplattform liegt auf 12 | nein |
| 13 | Fire Raiser | 13 | **ja** |

**Sechs von elf stimmen exakt, fünf nicht — und drei Zellen mit Inhalt bleiben
leer.** Damit ist belegt: **`dbButtons +216` ist im Arbeitermenü nicht die
Position.** In der Kaserne ist es das nachweislich (dort hat jede Verlegung
des Bannerträgers exakt gewirkt), im Arbeitermenü nicht.

Nicht weiter raten. Alles, was ich ins Arbeitermenü gelegt habe, ist
unsichtbar geblieben: Holzturm (3), Palisade (6), Klaue (5), Plattform (12) —
und der Stall verschwand, sobald ich ihn von 10 auf 6 zog. Die beiden
sichtbaren Nichtübereinstimmungen (Settlement 7 → Position 0, Stall 10 →
Position 3) sind jeweils genau eine Reihe nach oben verschoben; das ist der
einzige erkennbare Zusammenhang und reicht als Regel nicht aus.

**Nächster Schritt:** die Auswertung *dieses* Panels im Code finden, getrennt
von der Kaserne. Nicht wieder über Control-IDs (701) oder FormIndex (110–123)
suchen — beides waren Zufallstreffer.

### UI-Klasse `t[29]` ist auch bei Einheiten die Freigabe

Bestätigt am Greek General: Javelin, Pädagoge und Spartaner haben in der
Spartaner-Akademie alle `t[29] = 5` und erscheinen; der General hatte `0` und
fehlte, obwohl Bauliste, Button, Kosten und `+392` in Ordnung waren. Auf `5`
gesetzt.

**Merksatz:** `t[29]` beim Anlegen jedes neuen Eintrags mitprüfen — es ist
bisher zweimal die Ursache für „erscheint einfach nicht" gewesen.

### `dbobjects +596` = „vom Spieler herstellbar"

Gefunden über einen Zweiseiten-Vergleich (`tools/rnf_split.pl`): sichtbare
Akademie-Einheiten gegen den unsichtbaren Greek General.

Über alle 509 Objekte, die in einer Bauliste stehen *und* einen Techtree-
Eintrag mit echten Kosten haben: **467 tragen `1`, 38 tragen `0`** — und die 38
sind fast ausnahmslos „**Spawned**"-Varianten (`A - Inf03 - Spartan (Greek)
(Spawned)` und Geschwister), also Einheiten, die ein Szenario per Skript setzt
und die niemand ausbildet. Dazu ein Projektil. Die Bedeutung ist damit klar.

Der `Greek General` war das einzige Objekt unserer Baustellen mit `0`. Auf `1`
gesetzt. Holzturm, Palisade und Belagerungsplattform stehen dort bereits auf
`1` — für die ist es also **nicht** die Ursache.

Damit sind jetzt vier Bedingungen bekannt, die eine Einheit erfüllen muss, und
alle vier sind schon einmal einzeln die Ursache gewesen:
Bauliste, Techtree-Eintrag mit Kosten, `dbtechtree[29]` (UI-Klasse),
`dbobjects +392` (Ein/Aus) und `dbobjects +596` (herstellbar).

### Arbeitermenü: Sperre liegt weder in `dbobjects` noch in `dbtechtree`

Zweiseiten-Vergleich über die vom Nutzer bestätigten Gruppen — sichtbar
(Tower 1x1, Dock, Stall, Kaserne, Settlement, Statue, Akademie, Basar, Mauer)
gegen unsichtbar (Holzturm, Palisade, Belagerungsplattform):

* **`dbobjects`: 0 von 478 Feldern trennen die Gruppen sauber.**
* **`dbtechtree`: 0 von 44 Feldern trennen die Gruppen sauber.**

Der Inhalt des Arbeitermenüs wird also nicht in diesen beiden Tabellen
entschieden. Zusammen mit der Beobachtung, dass die angezeigten Positionen
Lücken haben (4, 5 und 12 bleiben leer), spricht das für eine **feste Liste von
Kategorien**, in die die Engine pro Zivilisation ein Gebäude einsetzt.

**Laufender Test:** In `db\dbcivspecificunitdefines.dat` (Kategorie →
Zivilisation) wurde Kategorie 16, Eintrag Griechen, von `Tower 1x1 (Greek)`
(Record 123) auf `Tower Timber (SP) (Greek)` (Record 829) umgebogen. Erscheint
im Arbeitermenü an Position 1 statt des Steinturms der Holzturm, ist die
Tabelle die Quelle des Menüs — dann lässt sich das Menü durch **Austauschen**
steuern, nicht durch Hinzufügen. Bleibt das Menü unverändert, ist auch diese
Tabelle es nicht, und die Liste steckt im Code.
Zurücknehmen: `Data/db/dbcivspecificunitdefines.dat` löschen.

### Arbeitermenü — dritte Quelle ausgeschlossen, Sackgasse

Der Test mit `db\dbcivspecificunitdefines.dat` (Kategorie 16 der Griechen vom
Steinturm auf den Holzturm umgebogen) hat **nichts** verändert. Damit ist auch
diese Tabelle nicht die Quelle des Arbeitermenüs. Datei wieder gelöscht.

Stand der Ausschlüsse für das Arbeitermenü:

| Kandidat | Ergebnis |
|---|---|
| Bauliste des Citizen-Objekts (`+908`/`+1212`) | Ergänzungen bleiben wirkungslos |
| `dbobjects` (alle 478 int32-Felder) | 0 Felder trennen sichtbar/unsichtbar |
| `dbtechtree` (alle 44 Felder) | 0 Felder trennen sichtbar/unsichtbar |
| `dbButtons +216` | wirkt (ein verschobener Stall verschwindet), ist aber nicht die Position (6 von 11 Positionen passen, 3 belegte Zellen bleiben leer) |
| `dbcivspecificunitdefines` (Kategorie → Ziv) | Umbiegen ändert nichts |

**Bewertung:** Das Arbeiter-Baumenü ist mit Datenmitteln bisher nicht
erweiterbar. Vier Sitzungen, jeweils mehrere Ingame-Tests, kein Fortschritt.
Bevor hier weitergemacht wird, muss die Panel-Auswertung im Code gefunden sein
— und die drei naheliegenden Einstiege (Control-IDs 701+, FormIndex 110–123,
Button-Zugriffshelfer `FUN_0056fb10`) waren allesamt Sackgassen.
**Empfehlung: ruhen lassen**, bis es einen neuen Einstieg gibt.

### Vier Flags, die eine Einheit ausbildbar machen

Aus dem Zweiseiten-Vergleich Greek General (unsichtbar) gegen Javelin,
Pädagoge und Spartaner (sichtbar), jeweils gegengeprüft über alle 148
ausbildbaren Einheiten:

| Feld | Bedeutung | Ausnahmen |
|------|-----------|-----------|
| `+392` | Ein/Aus (`-1` = an, `100000` = nie) | keine |
| `+596` | vom Spieler herstellbar | 38 von 509, fast alle „Spawned"-Varianten |
| `+608` | ausbildbare Einheit | 3 von 148: zwei Minen-Gebäude und der General |
| `+768` | ausbildbar (zweites Flag) | 22 von 148, alle „Spawned" |

Der Greek General war auf allen drei letzten `0`, wo jede funktionierende
Einheit `1` trägt. Alle drei gesetzt; er stimmt jetzt in jedem bekannten Feld
mit Javelin und Pädagoge überein. Erscheint er danach immer noch nicht, ist die
Ursache mit Feldvergleichen nicht mehr zu finden.

### Text statt Icon: `db\string-graphic info.txt` ist ein Entwickler-Report

Die Datei ist kein Zuordnungstabelle, sondern ein **Prüfbericht der
Entwickler**: pro Objekt eine Zeile `UDF / Objekt / String`, und wo der Name
fehlt, steht `Bad String(NNNN)`. Sie erklärt, warum manche Einheiten im Menü
Text statt eines Namens zeigen.

**Als Erklärung für Unsichtbarkeit taugt sie nicht:** Spartaner
(`Bad String(3110)`), Pädagoge (`2765`) und Javelin (`5572`) stehen ebenfalls
drin und erscheinen trotzdem. Fehlender Name ist kosmetisch, keine Sperre.
Die Button-Icontexturen sind übrigens alle vorhanden (geprüft für
`but_ySwordBannerT`, `but_yMGeneralT`, `but_yTowerT`, `but_yWoodSpikes` u. a.),
es scheitert also nicht an fehlenden Dateien.

### Greek General: alle Kampagnen-Flags abgeräumt

Zweiseiten-Vergleich gegen Javelin, Pädagoge und Spartaner, mehrfach
wiederholt, jeweils gegengeprüft über alle 148 ausbildbaren Einheiten:

| Feld | General | funktionierende Einheiten | Gegenprobe |
|------|---------|---------------------------|-----------|
| `+596` | 0 | 1 | 467 von 509 tragen 1; die 0er sind „Spawned"-Varianten |
| `+608` | 0 | 1 | 145 von 148 tragen 1 |
| `+768` | 0 | 1 | 126 von 148 tragen 1, Rest „Spawned" |
| `+592` Byte 1 | 1 | 0 | gesetzt bei **2** von 148: General und Sichelwagen (beides Kampagne) |
| `+916` Byte 2 | 1 | 0 | gesetzt bei **1** von 148: nur dem General |

Alle fünf angeglichen. Danach unterscheiden ihn nur noch drei Felder von den
funktionierenden Einheiten, und keines davon kann Sichtbarkeit steuern:
`+588` ein Float (0,669 gegen 1,0) und `+612`/`+616` seine eigenen Sound-IDs.

**Wenn er damit immer noch nicht erscheint, ist die Ursache kein Feld im
Objekt-Record** — dann gilt für ihn dasselbe wie fürs Arbeitermenü: ruhen
lassen, bis es einen Einstieg über den Code gibt.

### Vorgehen bei Kampagneneinheiten: klonen statt Felder angleichen

Der `Greek General` liess sich durch Angleichen einzelner Felder nicht
ausbildbar machen — fünf Kampagnen-Flags wurden nacheinander gefunden und
gesetzt (`+596`, `+608`, `+768`, `+592` Byte 1, `+916` Byte 2), er erschien
trotzdem nicht. Auch `dbtechtree[29]`, `+392`, Bauliste, Kosten, Button und
Icon-Textur waren in Ordnung, und `db\string-graphic info.txt` zeigt, dass ein
fehlender Name (`Bad String`) kosmetisch ist und funktionierende Einheiten
ebenso betrifft.

**Konsequenz: nicht mehr Feld für Feld nachziehen, sondern den kompletten
2012-Byte-Datensatz einer nachweislich funktionierenden Einheit kopieren** und
nur die Identität zurückschreiben. Dafür gibt es `tools/rnf_clone.pl`.

Zurückgeschrieben werden müssen:

* **`+912` die eigene id** — Techtree-Eintrag und alle Baulisten verweisen darauf
* **`+0` ein eigener, eindeutiger Name** — die Engine führt eine
  Namens-Registry (`FUN_00a04110`), zwei Datensätze mit gleichem Namen sind
  ein Risiko
* `+300` Button und `+304` Grafikeintrag, sonst sieht die Einheit aus wie das
  Original

Angewendet: `Greek General` = byteweise Kopie des `Military Trainer (Greek)`,
mit eigener id 5176, eigenem Button 2916, eigenem Modell `men_ySPAgeneral`,
Trainer-Rate `+1152` auf 0,20 statt 0,05 und Radius `+1156` auf 10 m statt 3 m.
Damit stimmen alle unbekannten Flags automatisch, weil sie aus einer Einheit
stammen, die im Spiel funktioniert.

**Wenn auch das nicht erscheint**, liegt es nicht mehr am Datensatz, sondern an
der Identität selbst (id 5176) oder an etwas ausserhalb von `dbobjects` —
dann hier aufhören.

### Weitere ausgeschlossene Spur

`FUN_00a04110`, die Quelle von `template+0xfc`, ist eine **Namens-Registry**
(Map Name → Handle, legt bei Bedarf an, Vorgabewert 5000). Kein Menüplatz.
Damit ist auch dieser Weg zur Panel-Position zu.

### WARNUNG: Klonen mit fremdem Modell stürzt ab

Der Klon-Versuch (Datensatz des `Military Trainer` auf den `Greek General`,
aber dessen Modell `men_ySPAgeneral` beibehalten) hat das Spiel **zum Absturz
gebracht**, sobald die Spartaner-Akademie fertig gebaut war. Vollständig
zurückgenommen: Objekt-Datensatz, beide Baulisten und der Techtree-Eintrag des
Generals stehen wieder im Originalzustand.

**Erklärung:** Der 2012-Byte-Datensatz enthält nicht nur Spielwerte, sondern
auch Verweise, die zum Modell gehören — Animationssätze, Sounds, Aufsatzpunkte
(u. a. `+612`, `+616`, `+620`, `+624`). Kopiert man den Datensatz und lässt
`+304` auf ein *anderes* Modell zeigen, verweisen diese Felder auf Animationen,
die es in diesem Modell nicht gibt.

**Regel: `tools/rnf_clone.pl` nur mit dem Modell der Quelle verwenden.**
Wer das Aussehen ändern will, muss `+304` *und* alle modellgebundenen Verweise
mitziehen — welche das genau sind, ist ungeklärt.

**Aufschlussreich ist der Absturz trotzdem:** mit seinem Originaldatensatz
*fehlte* der General nur; nach dem Klonen wurde er offenbar verarbeitet und
stürzte erst beim Zeichnen ab. Das spricht dafür, dass der Klon-Ansatz die
Sichtbarkeit tatsächlich löst und nur die Modell-Verweise das Problem sind.
Ein Klon **mit** dem Trainer-Modell wäre der nächste Versuch — dann sieht der
General allerdings aus wie ein Pädagoge.

**Nachtrag:** Genau so umgesetzt - Klon mit dem Trainer-Modell (`gfx=154`),
eigene id 5176, eigener Button 2916, Rate 0,20, Radius 10 m. Die Vorgabe von
`rnf_clone.pl` wurde umgedreht: das Modell der Quelle wird jetzt
standardmässig mitkopiert, ein fremdes Modell erfordert ein ausdrückliches
`gfx=<n>` und ist als Absturzrisiko dokumentiert.

### Identitätsfelder: was ein Klon nicht mitkopieren darf

Gemessen über alle 3079 Records — Anzahl verschiedener Werte pro Feld:

| Feld | verschiedene Werte | Bedeutung |
|------|--------------------|-----------|
| `+100` | 2164 | pro Objekt eigene ID (vermutlich String) |
| `+116` | 2164 | dito |
| `+304` | 1739 | Index in `dbgraphics` — 1:1 mit dem Objekt |
| `+912` | 1909 | Objekt-ID; Techtree und Baulisten verweisen darauf |

Alle übrigen 474 Felder haben deutlich weniger als die Hälfte an
verschiedenen Werten, sind also Spielwerte und keine Identität.

**Zwei Abstürze, zwei verschiedene Ursachen, beide aus dieser Tabelle:**

1. Klon mit *fremdem* Modell (`+304` behalten, Rest vom Pädagogen): die
   Animations-, Sound- und Aufsatzverweise im Datensatz gehören zum Modell der
   Quelle und zeigen ins Leere. Absturz beim Zeichnen.
2. Klon mit Modell der Quelle (`+304` mitkopiert): jetzt beanspruchen zwei
   Objekte denselben `dbgraphics`-Eintrag — die Tabelle ist aber 1:1 (2477
   Einträge, je einer pro Objekt, mit Rückverweis bei `+204`). Ebenfalls
   Absturz. Zusätzlich waren in beiden Versuchen `+100` und `+116` doppelt
   vergeben, weil ich sie nicht als Identität erkannt hatte.

`tools/rnf_clone.pl` bewahrt jetzt `+100`, `+116`, `+300`, `+304` und `+912`.

**Der verbleibende Widerspruch:** Ein Klon braucht ein Modell, das zu den
kopierten Animationsverweisen passt (also das der Quelle), *und* einen eigenen
`dbgraphics`-Eintrag (weil die Zuordnung 1:1 ist). Beides zusammen geht nur,
wenn man zusätzlich **den Grafik-Eintrag des Ziels auf das Quellmodell
umbiegt** — also `dbgraphics`-Record des Ziels vom Quell-Record klonen und
dessen eigenen Index bei `+204` zurückschreiben. Ungetestet, und es setzt
voraus, dass `Data\db\dbgraphics.dat` als lose Datei überhaupt geladen wird.

### Laufender Test: wird `db\dbgraphics.dat` als lose Datei geladen?

Im Grafik-Record 157 (`A - b  Tower 1x1 (Greek)`) wurde der Modellname von
`bld_yM1X1tower_00` auf `bld_yE1x1tower_02` geändert — derselbe Gebäudetyp
einer anderen Zivilisation, also identischer Animationssatz und damit kein
Absturzrisiko. Beide Modelle existieren im Archiv (`units\*.udf`).

* Sieht der griechische 1x1-Turm im Spiel **ägyptisch** aus → die Datei wird
  lose geladen.
* Sieht er unverändert aus → sie wird es nicht, so wie
  `dbcivspecificunitdefines.dat`.

Zurücknehmen: `Data\db\dbgraphics.dat` löschen.

Davon hängt ab, ob ein Klon mit eigenem Grafik-Eintrag überhaupt möglich ist
(siehe „Identitätsfelder" oben).

**Ergebnis des Tests: ja.** Der griechische Turm sah im Spiel ägyptisch aus
(mit griechischen Soldaten darauf — die Spielerfarbe kommt von der Einheit,
nicht vom Gebäudemodell). `Data\db\dbgraphics.dat` als lose Datei wirkt.
Damit sind **Modelltausche möglich**, solange der Animationssatz passt
(gleicher Objekttyp einer anderen Zivilisation ist sicher). Test
zurückgenommen.

### Klon dritter Versuch — beide Absturzursachen ausgeräumt

Aufbau:

* `dbgraphics[821]` (der **eigene** Eintrag des Generals, eigene ID 3918) zeigt
  jetzt auf `men_yMmilitarytrainer` statt `men_ySPAgeneral`.
  → Modell passt zu den kopierten Animationsverweisen, **und** der Eintrag
  bleibt exklusiv seiner. Beide Absturzursachen entfallen.
* `dbobjects`: Datensatz des Pädagogen kopiert, Identität zurückgeschrieben —
  `+100=4013`, `+116=915`, `+300=2916`, `+304=821`, `+912=5176`, eigener Name.
  Nachgeprüft: jeder dieser Werte kommt im ganzen Datenbestand **genau einmal**
  vor.
* Rate `+1152` = 0,20 statt 0,05, Radius `+1156` = 10 m statt 3 m.
* Techtree: Zeit 250, Kosten 110000, `t[29]=5`.

Merksatz für künftige Klone: **erst dem Ziel einen eigenen `dbgraphics`-Eintrag
auf das Quellmodell zeigen lassen, dann den Objekt-Datensatz klonen.**

### `dbtechtree[1]` ist die Objektkategorie — `4` heisst Kulisse

Der Klon (dritter Versuch) stürzte **nicht** mehr ab, der General erschien aber
weiterhin nicht. Da sein Datensatz zu diesem Zeitpunkt byteweise dem des
Pädagogen entsprach — bis auf die fünf Identitätsfelder — musste die Ursache
ausserhalb des Objekt-Datensatzes liegen.

Gefunden im Techtree-Eintrag, Feld `[1]`:

| Wert | Anzahl | Inhalt (Stichprobe) |
|------|--------|---------------------|
| 4 | 819 | `Cinematic - Swordsman`, `Cinematic - Minotaur`, `Ruins 01`, `Ruins Burned` — **Kulissen und Zwischensequenzen** |
| 5 | 496 | normale Einheiten und Gebäude (Javelin, Bannerträger, Turm) |
| 6 | 67 | Belagerungsgerät und der Military Trainer |
| 8 | 53 | u. a. der Spartaner |

**Der Greek General stand auf 4** — in derselben Schublade wie Ruinen und
Zwischensequenz-Figuren. Auf `6` gesetzt, passend zum geklonten Pädagogen.

Damit sind es **sechs** Bedingungen, die eine Kampagneneinheit erfüllen muss,
und jede war schon einmal einzeln die Ursache:
Bauliste · Techtree-Eintrag mit Kosten · `t[1]` Kategorie · `t[29]` UI-Klasse ·
`dbobjects +392` Ein/Aus · `+596`/`+608`/`+768` Herstellbar-Flags.

Nebenbei ausgeschlossen: Eltern-IDs im Techtree sind ein **eigener
Nummernraum** — nur 664 von 2473 fallen zufällig mit einer Objekt-ID zusammen
(der Spartaner „stammt" so rechnerisch von einem Wohnhaus ab). Dass id 5176
als Elternknoten auftaucht, ist bedeutungslos.

### Greek General: aufgegeben

Sechs Bedingungen erfüllt (Bauliste, Preis, `t[1]=6`, `t[29]=5`, `+392`,
`+596`/`+608`/`+768`), Datensatz byteweise ein Klon des Pädagogen, eigener
Grafik-Eintrag auf dem Quellmodell, keine doppelte ID — er erscheint trotzdem
nicht, stürzt aber auch nicht mehr ab. Es muss eine **siebte Bedingung** geben,
die ich nicht gefunden habe. Vollständig zurückgenommen.

**Lehre für künftige Versuche:** Die sechs bekannten Bedingungen sind
*notwendig, aber nicht hinreichend.* Eine Kampagneneinheit, die möglichst wenige
davon verletzt, hat die besseren Chancen — deshalb `tools/rnf_candidates.pl`,
das jede nicht erreichbare Einheit auflistet und dazuschreibt, welche
Bedingungen ihr noch fehlen.

### Sichelwagen für die Griechen

`A - Cav00 - Scythe Chariot (Persian)` (id 10003) ist **keine**
Kampagneneinheit — er ist im persischen Stall regulär baubar. Damit war es der
einfache Fall: Objekt in die Bauliste des griechischen Stalls (MP und SP),
Button 445 von Zelle 0 auf 8 (frei in allen vier Ställen, keine Kollision).

Werte: 1500 HP, 115 Schaden, Familie „Mounted Spear", Sonderverhalten
`A-Scythe Chariot`, Kosten 100000, Bauzeit 150. Modell `cav_yPscythechariot` —
das Spiel hat **kein griechisches Streitwagenmodell**, er sieht also persisch
aus.

**Nebenbefund, der eine frühere Aussage korrigiert:** Der Sichelwagen hat
`+768 = 0` und `t[1] = 9` und ist trotzdem regulär baubar. `+768` ist also
**keine** notwendige Bedingung, und `t[1]` muss nicht 5 sein (7 und 9 kommen
bei Kavallerie vor). Von den sechs Bedingungen sind damit nur noch fünf
belegt, und auch die sind nur notwendig, nicht hinreichend.

`A - Cav00 - Camel Supply (Rome)` wurde geprüft und verworfen: Schaden 0, kein
Sonderverhalten, kein Flächeneffekt — ein Tragtier ohne Spielwirkung.

### Zivilisationsfilter: es gibt KEIN Civ-Feld im Objekt-Record

Der Sichelwagen (persisch, im persischen Stall regulär baubar) erschien nach
dem Eintrag in die griechische Stall-Bauliste **nicht**. Rückblickend waren
*alle* geglückten Ergänzungen gleiche Zivilisation: griechischer Javelin in die
griechische Akademie, jeder Bannerträger in die Baracke seiner eigenen
Zivilisation. Und jede Baracke enthält die Schwertkämpfer aller vier
Zivilisationen auf Zelle 7, sichtbar ist immer nur die eigene — das Spiel
filtert also.

**Gesucht und nicht gefunden:** ein Zivilisationsfeld im Objekt-Record.
Weder über alle ~300 Objekte je Zivilisation noch über zusammengehörige
Vierergruppen (Schwertkämpfer, Speerkämpfer, Baracke, Stall, Turm je
Zivilisation) ist ein Feld konstant pro Zivilisation und verschieden zwischen
ihnen. Der Filter läuft **nicht** über `dbobjects`.

**Verdacht: das Eltern-Feld `[-1]` im Techtree ist die Voraussetzung.**
Auffällig ist, dass der erfolgreich eingebaute Javelin sich seinen
Elternknoten **3585** mit `Sword Infantry (Level 1 Greek)` teilt — also mit
einer Einheit, die jeder Grieche von Beginn an bauen kann. Objekte, die nicht
erscheinen, hängen an eigenen Knoten: Sichelwagen 5276 (persisch),
Greek General 5582, beide von nichts sonst benutzt.

**Laufender Test:** Eltern des Sichelwagens von 5276 auf 3585 gesetzt.
Erscheint er danach im griechischen Stall, ist der Mechanismus gefunden — und
damit ein Rezept, um Einheiten zwischen Zivilisationen zu portieren. Dass er
den Persern dabei verloren geht, ist der erwartete Preis und wäre die
Bestätigung.
Zurücknehmen: `tools/backup/dbtechtree_v16_backup.dat` zurückkopieren.

---

## Sitzung 2026-09-11 — Aufwertungssystem entschlüsselt, zwei Korrekturen

### Korrektur 1: Das Eltern-Feld `[-1]` ist NICHT der Zivilisationsfilter

Test: Eltern des Sichelwagens von 5276 (persisch) auf 3585 (Voraussetzung des
griechischen Standard-Schwertkämpfers) gesetzt, Sichelwagen in die griechische
Stall-Bauliste. Ergebnis im Spiel: **bei den Griechen nicht sichtbar, bei den
Persern unverändert vorhanden.** Vollständig zurückgenommen.

Weitere Belege, dass `[-1]` nicht die Freischaltung ist: Eltern-IDs lösen sich
als Eintrags-IDs zu Unsinn auf (der Sichelwagen „stammt" von einer griechischen
Festung ab), und Bannerträger wie persischer Javelin funktionieren mit ihrem
eigenen, von nichts sonst benutzten Elternknoten. Der Javelin-Fix von damals
hatte 8 Felder auf einmal geändert und beweist deshalb nichts über `[-1]`.

**Ein Zivilisationsfeld gibt es auch byteweise nicht**, weder in `dbobjects`
(Einzelbytes und 16-Bit über zusammengehörige Vierergruppen) noch im
Techtree-Eintrag. Die Bitmaske bei Template `+0x64` wird im Konstruktor mit 0
initialisiert und zur Laufzeit gefüllt, nicht aus der Datei gelesen.
**Einheiten zwischen Zivilisationen zu portieren geht mit Datenmitteln bisher
nicht.** Innerhalb einer Zivilisation funktioniert es.

### Korrektur 2: Geteilte Grafik-Einträge sind erlaubt

Die Annahme „`dbgraphics` ist 1:1 mit den Objekten, zwei Objekte auf einem
Eintrag stürzen ab" war **falsch**. Von 1738 benutzten Grafik-Einträgen werden
164 von mehreren Objekten geteilt, 74 davon von zwei gleichzeitig baubaren
Einheiten (z. B. `Tower Catapult (Egypt)` und seine `(Min Range 10)`-Variante,
`Sword Infantry (Level 5 Greek)` und dessen `(Elite)`-Duplikat). Der zweite
Absturz beim General hatte also eine andere Ursache — wahrscheinlichster
Kandidat bleiben die mitkopierten Identitätsfelder `+100`/`+116`.

Konsequenz für `tools/rnf_clone.pl`: `+304` darf bewusst auf den Grafik-Eintrag
der Quelle gesetzt werden (`f304=<n>`); das ist sogar der sicherste Weg, weil
Modell und Animationsverweise dann garantiert zusammenpassen.

### Das Aufwertungssystem

**`dbtechtree` `t[1]` = Stufe + 4.** Über alle Einheitenlinien ausnahmslos:
Level 1 → 5, 2 → 6, 3 → 7, 4 → 8, 5 → 9. Der Parser setzt Laufzeitgrenzen 5 und
9 (`FUN_008d8260`: `+0x2124 = 5`, `+0x2128 = 9`). Der Greek General stand auf 4
— unterhalb des spielbaren Bereichs, zusammen mit Kulissen und
Zwischensequenz-Objekten.

**Jede Stufe ist ein eigenes Objekt mit eigenem Namen.** Griechische
Schwertkämpfer Level 1–5: *Hypaspist → Improved Hypaspist → Companion →
Improved Companion → Royal Guard*. Die Namen stehen in `Language2.dll`
(String-ID = `dbobjects +296` = Techtree `[18]`); `Language.dll` enthält sie
nicht.

**`[11]` ist die Voraussetzung — für Einheiten und Forschungen.**
`Sword Infantry (Level 2 Greek)` hat `[11] = 7147` = `A - UP - Inf Sword 2
(Greek)`; `A - UP - Inf Sword 3` hat selbst wieder `[11] = 7147`. Das ist die
Aufwertungskette.

**Forschungen sind gewöhnliche 44er-Einträge, deren Name in den 100 Byte davor
steht,** gefolgt von einem Anhang mit zwei Listen, jeweils mit vorangestellter
Anzahl:

| ab Eintragsbasis | Inhalt |
|---|---|
| `+352` | Anzahl, dann **Record-Indizes der Gebäude**, die die Forschung anbieten |
| danach | Anzahl, dann **was sie freischaltet** (Einheiten-IDs und Folgeforschung) |

Beispiel `UP Sword 2 (Greek)`: 8 Gebäude = die 8 Kasernen (MP/SP je
Zivilisation), freischaltet `[8467 UP Sword 3, 8425, 7080 Sword L2]`. Der Anhang
hat variable Länge; **Werte austauschen ist sicher, Listen verlängern würde
alle folgenden Bytes verschieben.**

**Ins Gebäudemenü kommt eine Forschung wie eine Einheit:** ihre ID steht in der
Bauliste des Gebäudes (`+908`/`+1212`). Ihr Button ist Techtree `[16]`, der
Menüplatz dessen `+216`. Die obere Reihe (0–6) trägt die Aufwertung der
Einheit direkt darunter (Schwert-Upgrade 0 über Schwertkämpfer 7).

**18 Forschungen hängen an keiner Einheit** und eignen sich zum Umwidmen, u. a.
`A - UP - Cav Spear 2/3 (UNUSED)`, `A - UP - Military Trainer (Greek)` (in der
SP-Akademie eingehängt, schaltet nichts frei) und die Heldenlevel-Forschungen
`A - UP - Hero Stamina Regeneration (Normal) (Level 2 … 6-10)`. Außerdem gibt
es einen fertigen Button `A - UP - Javelin Thrower (Greek)` (Nr. 1) ohne
Techtree-Eintrag — geplant, nie gebaut.

**Beschreibungstexte:** kein Objekt-, Button- oder Techtree-Feld löst sich zu
einem Beschreibungstext auf. `Language2.dll` beschreibt sich selbst als
„contains Unit & Tech Names". Änderbar ist also der Name. `+116` ist *keine*
String-ID (löst sich zu Unsinn wie „G_House Halftile 1L" auf). Der
Entwickler-Report `db\string-graphic info.txt` ist veraltet: er meldet
„Bad String" auch für Namen, die im Spiel existieren.

### Laufender Test: „Bannerträger Stufe 2" (nur Griechen)

* **Forschung** `A - UP - Cav Spear 2 (UNUSED)` (id 7049, @938696) umgewidmet,
  ohne Längenänderung: Gebäudeliste Ställe → die 8 Kasernen, Freischaltliste
  `8027` → `10427`, Button `210` → `175` („Generic Level up", vorher
  unbenutzt, jetzt Zelle 4 über dem Bannerträger), Name-String → 2223. Aus allen
  8 Stall-Baulisten entfernt, in die griechische Kaserne (MP/SP) eingetragen.
* **Einheit** auf dem ungenutzten Duplikat `Sword Infantry (Level 5 Greek)
  (Elite)` (id 10427, @360152; kein Szenario, kein Techtree-Verweis außer dem
  eigenen): Objekt-Datensatz vom griechischen Bannerträger geklont,
  Identität `+100`/`+116`/`+912` behalten, Button 2441 und Grafik 1867 **vom
  Bannerträger mitbenutzt**, Trainer-Rate 0,10 statt 0,05, Radius 10 m.
  Techtree-Eintrag (@1164416): Felder `[1]…[42]` vom Bannerträger, `[11] = 7049`.
  In die griechische Kaserne (MP/SP) eingetragen.
* Heldenlevel-Kopplung ist **noch nicht** enthalten — erst muss die
  Kette Forschung → Einheit belegt sein.
* Zurücknehmen: `tools/backup/dbobjects_v36_backup.dat`,
  `dbtechtree_v17_backup.dat`, `dbButtons_v19_backup.dat` zurückkopieren.

### Ergebnis: die umgewidmete Forschung erschien nicht

Im Spiel war weder beim Bannerträger noch beim Javelin ein Aufwertungsfeld zu
sehen. (Beim Javelin war auch nichts eingebaut, dessen Fehlen sagt also nichts.)
Damit sind zwei Ursachen möglich: die Zelle wird nicht gezeichnet, oder eine
Forschung braucht mehr als ihren Eintrag in der Bauliste des Gebäudes.

**Kontrollversuch (läuft):** Die *funktionierende* Schwertkämpfer-Aufwertung
(Button 213, alle vier Stufen) wurde von Zelle 0 auf **Zelle 4** verschoben —
genau den Platz, auf dem die neue Forschung unsichtbar blieb. Die neue
Forschung weicht auf Zelle 3 aus.

* Erscheint die Schwert-Aufwertung jetzt über dem Bannerträger → Zelle 4 wird
  gezeichnet, und die Ursache liegt in den Daten der neuen Forschung.
* Verschwindet sie ganz → die Zelle war das Problem, nicht die Forschung.
* Zusätzlich zeigt Zelle 3, ob die neue Forschung woanders sichtbar wird.

Zelle 0 bleibt bei den Griechen dann leer: dort liegen nur noch die
Schwert-Aufwertungen der anderen Zivilisationen, die ein griechischer Spieler
nicht sieht.

Zurücknehmen: `tools/backup/dbButtons_v20.dat` zurückkopieren.

## Sitzung 2026-09-15 (Remake) — weitere `dbobjects`-Felder

Per Nebeneinanderstellen von Schwert-/Speer-/Bogen-/Reiter-/Bürger-/Helden-Datensätzen
(`converter/.../tools/StatsProbe.java`) gefunden; typkonsistent, aber **nicht im Code bestätigt**.
Entfernungen in Spiel-Einheiten, 1 Einheit = 3,048 m (`UnitsPerMeter` 0,3281 der Modelle).

| Offset | Typ | Vermutete Bedeutung | Beispiele |
|---|---|---|---|
| +132 | f32 | Angriffsreichweite | Nahkampf 0,6 · Reiter 0,8 · Bogen 8 · Speerwerfer 10 |
| +136 | f32 | Sichtweite | 8–10 |
| +140 | f32 | Angriffsintervall (s) | Schwert 1,8 · Speer 2,1 · Bogen 4,0 · Reiter 1,0 |
| +148 | f32 | Bewegungsgeschwindigkeit | Bogen/Speer 0,8 · Schwert 1,0 · Reiter 1,4 |
| +156/+160 | f32 | Drehrate (rad/s)? | 12,2/14,0 · Reiter 7,0 |
| +192 | u32 | Angriffsart | 0 Nahkampf · 1 Fernkampf · 2 Reiter · 3 Gebäude · 5 Bürger |
| +560…+572 | u32 | Klassenboni? | Speer 6/24/24/6 (gegen Reiter) · Bogen 24/5/0/24 |
| +580 | u32 | Rüstung? | Infanterie 20 · Bogen 16 · Reiter 43 · Bürger 0 |
| +712/+716 | f32 | Grundfläche | Infanterie 0,45 · Reiter 0,75 × 0,95 |

## Sitzung 2026-09-15 (Remake) — Kosten im Tech-Tree

Konsistent über Einheiten und Gebäude, **nicht im Code bestätigt**:

| Feld | Deutung | Beispiele |
|---|---|---|
| `[10]` | Gold × 1000 | Hypaspist 19000 · Hoplit 24000 · Bogen 28000 · Reiter 42000 · Bürger 25000 · Kaserne 50000 · Stadtzentrum 60000 |
| `[5]` | Holz | Hypaspist 0 · Hoplit 25 · Bogen 30 · Kaserne 325 · Stadtzentrum 350 · Stall 275 |
| `[7]` | Bauzeit in Viertelsekunden | Bürger 35 · Infanterie 45–55 · Reiter 150 (Gebäude 0 – werden von Bürgern gebaut) |

Formationsbanner: `effects\sfx_ymbaseformationflag.edf` → Stange `sfx_yFlagpole_MODEL`, Fahne
`sfx_yMBaseFormationFlags_MODEL` mit `sfx_yBaseFormationFlags_T` (Atlas: Griechen, Ägypten, Persien, Rom).
Bäume sind SpeedTree (`speedtree\models\res_y*.spt`), nur Stümpfe liegen als `.gr2` vor.

## Sitzung 2026-09-16 (Remake) — Mauszeiger, Familien, Boni

* **`db\dbmousepointer.dat`**: 63 Datensätze à 224 Byte — `+0` Name (100 B), `+100`
  Texturpfad (100 B), danach sechs `u32` (laufende Nummern und zwei String-IDs; **kein**
  Hotspot). Zustände u. a. Normal, Attack, Attack Move, Wood, Mining, Build, Repair,
  RallyPoint, Heal, Garrison. Werkzeug: `converter/.../ExportPointers.java`.
* **Zeiger-Texturen**: teils normale DDS (auch **unkomprimiert**, fourCC 0 — der Dekoder
  liest jetzt die Kanalmasken), teils die dritte `.sst`-Variante: **15-Byte-Kopf + ganz
  normales TGA** (Typ 2, 32 bpp, Ursprung oben links) samt kleineren Mip-Stufen. Damit ist
  die in `REWRITE_OVERVIEW.md` offen gebliebene `.sst`-Variante geklärt.
* **`db\dbfamily.dat`**: 81 Familien à 412 Byte — Name (100 B), String-ID, eigene ID,
  danach 77 `u32`-Prozentwerte. Das ist die Bonus-/Trefferwahrscheinlichkeitsmatrix im Stil
  von Empire Earth (`dbweapontohit.dat` liefert dazu 6 Waffenarten: Shock, Arrow, Pierce,
  Gun, Laser, Missile — alle Werte dort 100). Familienzuordnung der Einheiten steht in
  `dbobjects +104` (Hypaspist = „Human Sword", Hoplit = „Human Spear", Reiter = „Lancer").
  **Offen**: Ab welcher Spalte die Werte den Familien 0..76 entsprechen, ließ sich per
  Byte-Vergleich nicht sicher festlegen (Kandidaten: Versatz 0 oder 2). Auffällig: in fast
  jeder Zeile steht 75 bei „Citizen"/„Tree" und 5000 bei „Mounted Spear"/„Medieval Field
  Weapon" — das 5000 spricht gegen einen reinen Multiplikator an dieser Stelle.
  Das Remake nutzt deshalb eine eigene, kleine Tabelle (`game/data/bonuses.json`).
* **Nicht** Boni: `dbobjects +560…+572` sieht nach Treffer-/Sound-Effektgruppen aus
  (Schwert 4/4/4/4, Bogen 24, alle Gebäude 26/20).
