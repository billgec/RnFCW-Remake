# Rise & Fall: Civilizations at War — Überblick für eine mögliche Neuimplementierung

Stand: 2026-09-03. Dieses Dokument ist die große Landkarte: was für Daten es
gibt, in welchem Format, wie schwer jedes Format ist, und wie die Engine
grob aufgebaut ist. Technische Detail-Specs (Byte-für-Byte) stehen in
[FORMATS.md](FORMATS.md) — hier geht es um den Überblick, damit nichts
vergessen wird, falls das Spiel irgendwann von Grund auf (z. B. in Java)
neu geschrieben wird, unter Wiederverwendung der Original-Grafiken/Assets.

**Ausgangslage:** `Data/data.ssa` (770 MB, verschlüsseltes Archiv, Version 3
des `rass`-Formats) enthält praktisch das gesamte Spiel: 12.150 Dateien.
Die Verschlüsselung ist vollständig gebrochen (siehe FORMATS.md) — alles
unten basiert auf tatsächlich extrahierten, gelesenen Dateien.

---

## 1. Asset-Inventar (aus `data.ssa`, 12.150 Dateien)

| Endung | Anzahl | Rohgröße gesamt | Was es ist | Aufwand für Rewrite |
|--------|-------:|------------------:|------------|----------------------|
| `.dds`  | 2.017 | 335 MB | Texturen (DirectX Surface, DXT-komprimiert) | **Keiner** — Standardformat, jede Grafik-Lib kann das lesen |
| `.gr2`  | 4.013 | 135 MB | 3D-Modelle & Animationen (Granny3D, RAD Game Tools) | **Mittel** — proprietär, aber öffentlich dokumentiert/Open-Source-Parser existieren (siehe Abschnitt 3) |
| `.scn`  | 31 | 89 MB | Szenarien/Zufallskarten-Vorlagen | **Keiner** — Format bereits vollständig geknackt (FORMATS.md) |
| `.udf`  | 1.891 | 69 MB | **Unit Definition Files** — Einheiten/Gebäude-Objekte (Modell-, Textur-, Sound-, Animationsverweise) | **Gering** — selbstbeschreibendes Tag-Format (`USTRB`), siehe Abschnitt 2 |
| `.sst`  | 1.664 | 55 MB | Texturen mit 12-Byte-Wrapper vor Standard-DDS | **Keiner** — Wrapper einfach überspringen |
| `.wav`  | 469 | 40 MB | Sounds, Standard-WAV | **Keiner** |
| `.tga`  | 75 | 37 MB | Texturen, Standard-Targa (meist große Umgebungstexturen) | **Keiner** |
| `.hdr`  | 16 | 7 MB | HDR-Umgebungs-/Himmelstexturen | **Keiner** — Standardformat |
| `.dat`  | 51 | 0,5 MB | Die eigentlichen Balancing-Tabellen (`dbobjects.dat`, `dbtechtree.dat`, …) | **Hoch** — kein generisches Format, jede Tabelle hat eigenen Parser (siehe FORMATS.md) |
| `.edf`  | 514 | 0,3 MB | Effekt-Definitionen (Partikel etc.) | **Gering** — gleiches Tag-Format wie `.udf` (Magic `ESTR` statt `USTRB`) |
| `.spt`  | 101 | 0,16 MB | SpeedTree-Baummodelle (3rd-Party-Middleware) | **Mittel** — SpeedTree-eigenes Format, SDK/Doku existiert extern |
| `.rmv`  | 108 | 0,16 MB | Zufallskarten-Generierungsskripte | **Keiner — reiner Klartext** (siehe Abschnitt 2) |
| `.xml`  | 104 | 0,14 MB | UI-Formulare (Fenster, Buttons, Layout) | **Keiner — reines XML** (siehe Abschnitt 2) |
| `.sdf`  | 919 | 65 KB | Sound-Definitionen (Verweise auf `.wav`, Lautstärke etc.) | vermutlich gering, ungeprüft |
| `.fx`   | 73 | 49 KB | HLSL-Shader-Dateien | **Keiner/Mittel** — je nachdem, welche Rendering-API die Neufassung nutzt |
| `.tai`  | 83 | 38 KB | KI-Verhaltensskripte (Zustandsmaschine) | **Keiner — reiner Klartext** (siehe Abschnitt 2) |
| `.env`  | 18 | 11 KB | Umgebungs-/Wetter-Definitionen | ungeprüft |
| `.phy`  | 1 | 0,4 KB | Physik-Konfiguration | ungeprüft |

**Kernaussage:** Ein überraschend großer Teil der *Spiellogik* (KI-Verhalten,
UI-Layout, Zufallskarten-Generierung) liegt als **reiner, lesbarer Text**
vor. Nur die Kern-Balancing-Tabellen (`db*.dat`, ~0,5 MB von 770 MB) und die
3D-Formate sind wirklich proprietär/binär.

---

## 2. Format-Steckbriefe (neu identifiziert in dieser Session)

### `.tai` — KI-Verhaltensskripte (Klartext!)

Beispiel (`unit ai scripts\grappling hook.tai`):

```
// Defending Building unit AI file
// Behaviors:
// Track enemy units in line of sight until in weapon range, then attack.

Idle
	EnemyUnitSpotted true(TrackEnemyUnit)
	PrepareToMove
	AlwaysTrue true(CalamityPreCast)
TrackEnemyUnit
	AlwaysTrue true(Idle)
CalamityPreCast
	allof(CalamityTargetStillValid,FacingEnemyUnit) true(CastCalamity)
	CalamityTargetStillValid false(ShouldIReturnToInitialContactLocation)
```

Grammatik (aus mehreren Beispielen abgeleitet, nicht formal verifiziert):
Zustandsname (Spaltenanfang) → darunter eingerückte Zeilen
`Bedingung[(Parameter)] true(NächsterZustand)` bzw. `false(...)`. `allof(...)`
kombiniert mehrere Bedingungen. `//` leitet Kommentare ein. Das ist im Kern
eine simple Zustandsmaschine — für eine Java-Neufassung müsste nur ein
kleiner Parser plus eine Bibliothek der benannten Bedingungen/Aktionen
(`EnemyUnitSpotted`, `CastCalamity`, …) geschrieben werden, keine
Binär-Reverse-Engineering nötig.

### `.xml` — UI-Formulare (reines XML!)

Beispiel (`user interface\civbuilder load civilization form.xml`):

```xml
<!--CivBuilder Load Civilization Form-->
<XMLForm ID="17" NumOfControls="6" NumOfGroups="1" LeftOffset="200"
  RightOffset="599" TopOffset="150" BottomOffset="449" DesignedWidth="800"
  DesignedHeight="600" UseToolTips="True" ...>
```

Direkt mit jedem XML-Parser lesbar. Beschreibt vermutlich komplette
Fenster-Layouts (Controls, Gruppen, Koordinaten) — die komplette UI-Struktur
liegt hier offen.

### `.rmv` — Zufallskarten-Skripte (reiner Klartext!)

Beispiel (`map scripts\(2) corridor of blood.rmv`):

```
//////////////////////////////////////////////////////////////////////
// (2) Corridor of Blood.rmv
// Input file for the (2) Corridor of Blood.scn map type.
// Copyright (c) 2005, Midway Home Entertainment, Inc. All rights reserved.
```

Nur den Kopf geprüft, aber eindeutig Text-basiert (Kommentar-Header im
C++-Stil). Zusammen mit den `EERandomMap*`-Funktionsnamen aus der EXE
(`EERMPIMGenerateResources`, `EERMPIMGenerateRamps`, …) vermutlich ein
domänenspezifisches Skript zur prozeduralen Kartengenerierung.

### `.udf` / `.edf` — Objekt-/Effekt-Definitionen (selbstbeschreibendes Binärformat)

Magic `"USTRB\0"` (Units/Buildings) bzw. `"ESTR"` (Effekte), danach eine
Folge benannter Einträge — **im Gegensatz zu den `db*.dat`-Tabellen sind
hier die Feldnamen als Strings im File selbst enthalten**:

```
"USTRB\0" | u32 0 | u32 nameLen | name
   dann wiederholt: u32 ? | u32 ? | u32 ? | u32 subNameLen | subName | Wert(e)...
```

Beispiel-Hexdump (`units\men_ymjavelin.udf`):

```
5553 5452 4200 0000 0f00 0000 6d65 6e5f   USTRB.......men_
794d 6a61 7665 6c69 6e00 0037 0000 0001   yMjavelin..7....
1500 0000 6d65 6e5f 794d 6a61 7665 6c69   ....men_yMjaveli
6e5f 4d4f 4445 4c00 0002 0000 0000 0000   n_MODEL.........
```

→ Name `"men_yMjavelin"` (15 Zeichen), darunter ein Unterfeld
`"men_yMjavelin_MODEL"` (21 Zeichen) mit Verweis auf die Modelldatei. Der
Rest der Datei besteht aus vielen weiteren solchen benannten Blöcken
(Sound-Trigger wie `sfx_yFootdust`, Animationsverweise wie `jav_walk_01`,
Statuswerte). **Nicht vollständig durchgeparst**, aber die Struktur ist
klar erkennbar und dank eingebetteter Namen deutlich leichter zu knacken
als die `db*.dat`-Tabellen — guter Kandidat für eine zukünftige Sitzung.

### `.sst` — Textur mit Streaming-Wrapper

12 Byte proprietärer Header, danach eine ganz normale `.dds`-Datei:

```
0109 0100 0000 0001 0000 0001 0000 0744   ← 12 Byte Header
4453 20 ...                                ← "DDS " Magic beginnt hier
```

Vermutlich Mip-Level-/Streaming-Metadaten (passend zu
`GETexture::GetMipLevelsToDrop`). Für eine Neufassung: einfach die ersten
12 Bytes verwerfen, Rest ist Standard-DDS.

---

## 3. Externe/Drittanbieter-Formate (nicht selbst reverse-engineeren)

* **`.gr2` (Granny3D)** — Middleware von RAD Game Tools (dieselbe Firma wie
  Bink Video, `binkw32.dll` liegt auch im Spielordner). `GrannySS.dll` ist
  im Spielverzeichnis vorhanden. Granny3D ist ein bekanntes, in vielen
  2000er-Jahre-Spielen verwendetes Format mit öffentlich verfügbaren
  Community-Parsern (z. B. diverse Open-Source-Granny2-Reader auf GitHub).
  Eigenes Reverse Engineering hier vermeiden — externe Tools/Bibliotheken
  suchen.
* **`.spt` (SpeedTree)** — Middleware von Interactive Data Visualization
  Inc. (`SpeedTreeRT.dll` im Spielordner, im Readme erwähnt: "Portions of
  this software utilize SpeedTree technology"). Ebenfalls ein bekanntes
  Format mit eigenem SDK.
* **`.bik` (Bink Video)** — für die Zwischensequenzen (`Data/Movies/*.bik`).
  Bink hat weit verbreitete Community-Decoder (z. B. `ffmpeg` seit einiger
  Zeit mit Bink-Unterstützung).

---

## 4. Engine-Architektur (aus RTTI-Klassennamen, ~2.260 Klassen in `RiseAndFall.exe`)

Namenskonvention: 2-Buchstaben-Modul-Präfix + PascalCase (z. B.
`GETextureManager` = Modul `GE` + `TextureManager`). Verteilung:

| Präfix | Anzahl | Bibliothek | Bedeutung |
|--------|-------:|------------|-----------|
| `EE`   | 2.090  | RiseAndFall.exe | **Spiellogik** (praktisch alles Spielspezifische) |
| `RT`   | 76     | RiseAndFall.exe | RTS-Kernsystem (Basis-Engine-Schicht) |
| `UI`   | 45     | LowLevelEngine.dll | generisches UI-Toolkit (Basisklassen, von `EEUI*` benutzt) |
| `NE`   | 17     | LowLevelEngine.dll | Netzwerk-Engine (Multiplayer/Sync) |
| `FS`   | 9      | LowLevelEngine.dll | Dateisystem (siehe FORMATS.md) |
| `GE`   | 7      | LowLevelEngine.dll | Grafik-Engine (Texturen, Rendering) |

Innerhalb von `EE` (Spiellogik), die größten Unter-Namensräume:

| Unter-Präfix | Anzahl | Beispiele | Vermutete Bedeutung |
|--------------|-------:|-----------|----------------------|
| `EEUI`  | 709 | `EEUIB3DModel`, `EEUIB3DDrawObject` | Spiel-UI (bei Weitem am größten — HUD, Menüs, Dialoge) |
| `EESE`  | 309 | `EESEAApplyElevation`, `EESEAChangeCiv`, `EESEAChangeTechCost` | **Scenario Effects** — die Trigger-Aktionen aus `.scn`-Dateien (siehe FORMATS.md, Block 2) |
| `EECP`  | 148 | `EECPACGatherPotentialMergeGroups`, `EECPAGOrder`, `EECPASGLand` | **Computer Player** — die Bot-KI selbst (hoch relevant für "gegen Bots spielen") |
| `EESM`  | 107 | `EESMAnimation`, `EESMAnimationManager`, `EESMACustomArea` | Szenario-/Animations-Verwaltung |
| `EEAI`  | 100 | `EEAIAStarBoundedPathGoal`, `EEAIAStarChokePointGoal` | Pfadfindung (A*-Suche, "Choke Points") |
| `EECC`  | 36  | `EECCGrapplingHook`, `EECCElephantToss`, `EECCArtilleryBarage` | **Calamity Components** — Spezialfähigkeiten/-angriffe (vgl. `dbcalamity.dat`) |
| `EEUC`  | 34  | `EEUCAirAnimal`, `EEUCAirplane`, `EEUCBasicCitizen` | **Unit Classes** — die C++-Klassenhierarchie der Einheitentypen |
| `EEPF`  | 31  | `EEPFOBuoyancy`, `EEPFODrag`, `EEPFOGravity` | Physik-Objekte |

**Für die Kran/Javelin-Frage besonders relevant:** `EECP*` (Computer-Player-
KI) entscheidet vermutlich, was Bots überhaupt zu bauen versuchen — auch
wenn ein Objekt technisch "buildable" ist, könnte die Bot-KI es nie
anfragen. Und `EESE*` (Scenario Effects) ist exakt der Mechanismus, mit dem
Kampagnen-Missionen Sonderverhalten scripten — beide Namensräume wurden in
dieser Session noch nicht im Detail durchsucht.

---

## 5. Stand der ursprünglichen Aufgabe (Javelin Thrower & Crane in Skirmish)

* ✅ `data.ssa` vollständig entschlüsselt (Verzeichnis + Dateiinhalte).
* ✅ Beide Objekte sind für alle 4 Standard-Zivilisationen vollständig in
  `dbobjects.dat` definiert (nicht kampagnenexklusiv auf Datenebene).
* ✅ Loser-Datei-Override-Mechanismus **code-verifiziert**: `FSPath::FindFile`
  durchsucht registrierte Verzeichnisse zuerst und kehrt sofort zurück,
  sobald eine Datei gefunden wird — Archivinhalte werden dann gar nicht
  mehr angefasst. Lose Dateien müssen unverschlüsselt/unkomprimiert
  vorliegen (das, was `rnf_ssa3.pl cat` ausgibt).
* ⏳ Der genaue Schalter (welches Byte/Feld in `dbtechtree.dat` oder
  `dbpremadecivs.dat` Standard-Skirmish von Kampagne/Szenario trennt) ist
  **nicht gefunden** — `dbtechtree.dat` ist ein Abhängigkeitsgraph, kein
  einfaches Flag-Array (siehe FORMATS.md, Abschnitt „dbtechtree.dat").
* 💡 Neue, in dieser Session nicht verfolgte Spur: `EECP*`-Klassen
  (Computer-Player-KI) und `EESE*` (Scenario Effects) könnten relevanter
  sein als reines Tech-Tree-Byte-Hacking — falls die Bot-KI nie versucht,
  Kran/Javelin zu bauen, würde ein reines "verfügbar machen" im Tech-Tree
  nicht reichen, ohne dass ein Mensch die Einheiten manuell baut.
  **Konkret bestätigt:** Es gibt eine Klasse `EECPBuildManager` (Bot-Bau-
  Entscheidungen) sowie eine bisher ungeprüfte Tabelle `db\dbcivspecai.dat`
  ("Civ Specific AI", Tabellen-ID `0x34`/52, Parser `FUN_005f7380`) — das
  ist der wahrscheinlichste Ort, an dem festgelegt ist, was die KI pro
  Zivilisation überhaupt in Erwägung zieht zu bauen. Falls der Spieler
  selbst baut (nicht der Bot), ist diese Tabelle vermutlich irrelevant und
  nur `dbtechtree.dat`/`dbpremadecivs.dat` zählen.

---

## 6. Werkzeuge & Umgebung (Referenz)

Alles in [FORMATS.md](FORMATS.md), Abschnitt „Werkzeuge" — kurz:

* `tools/rnf_ssa3.pl` — liest `data.ssa` (`list`/`extract`/`cat`).
* `tools/rnf_zl.pl`, `tools/rnf_ssa.pl` — `.scn`/`.ees` bzw. Kampagnen-Archive.
* `D:\rnf_re\` — Ghidra 12.1.3 + radare2 6.2.0 + JDK 21, Projekt mit beiden
  Binaries bereits importiert/analysiert (`D:\rnf_re\proj\RNF`), bereits
  dekompilierte Funktionen unter `D:\rnf_re\out\*.c`.

## 7. Priorisierte nächste Schritte (falls fortgesetzt)

1. **Klären, wer Kran/Javelin bauen soll — Spieler oder Bot?** Falls der
   *menschliche Spieler* selbst bauen will, ist nur `dbtechtree.dat`/
   `dbpremadecivs.dat` relevant (Punkt 3). Falls auch der *Bot* sie bauen
   soll, zusätzlich `db\dbcivspecai.dat` (KI-Bauentscheidungen,
   `EECPBuildManager`) prüfen — sonst bleibt das Gebäude ungenutzt, selbst
   wenn es technisch baubar ist.
2. **`.udf`/`.edf`-Format vollständig durchparsen** — dank eingebetteter
   Feldnamen deutlich leichter als die `db*.dat`-Tabellen, hoher Nutzen für
   eine Neufassung (das sind die eigentlichen Einheiten-/Gebäudedaten).
3. **`dbtechtree.dat`** (`FUN_008dff40`/`FUN_008df3f0`) feldweise fertig
   analysieren — nur falls Punkt 1 zeigt, dass es tatsächlich der richtige
   Hebel ist.
4. Für eine echte Neufassung: Granny3D- und SpeedTree-Reader/Bibliotheken
   evaluieren (nicht selbst schreiben), da beide Formate bereits von der
   Community erschlossen sind.
