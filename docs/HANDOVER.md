# Rise & Fall — Übergabe / Einstiegspunkt

**Diese Datei zuerst lesen.** Sie fasst zusammen, was funktioniert, was
nachweislich *nicht* funktioniert und warum — damit nichts doppelt versucht
wird. Technische Details stehen in `tools/FORMATS.md` (rund 2000 Zeilen); dort
ist der Abschnitt „Arbeitsregeln und gesicherter Stand" die Kurzfassung.

Stand: 2026-09-12

---

## 1. Zwei Projekte

| | Pfad | Zustand |
|---|---|---|
| **Mod** des Originalspiels | `D:\Code\Rise And Fall` | läuft, mehrere Erweiterungen aktiv |
| **Java-Neubau** | `D:\Code\RNFJava` | ~35 Dateien: Archiv, GR2-Modelle, DDS, Kamera, Shader, UI, `db\*.dat`-Leser, Schrift, Snapshot-Werkzeuge |
| Analyse (Ghidra) | `D:\rnf_re` | Projekt `proj\RNF.gpr`, Skripte in `scripts\`, Ausgaben in `out\` |

Gespielt wird **die Kopie unter `D:\Code\Rise And Fall`**, nicht `D:\GAMES\...`.

---

## 2. Aktuell ausgelieferter Stand

Lose Dateien unter `Data\db\` überschreiben die gleichnamigen im Archiv
`data\data.ssa`. Abweichung vom Original:

| Datei | Bytes |
|---|---|
| `dbobjects.dat` | 1263 |
| `dbtechtree.dat` | 93 |
| `dbButtons.dat` | 17 |

**Alles zurücksetzen:** die drei Dateien in `Data\db\` löschen — dann gilt
wieder der Originalzustand aus dem Archiv. Originale zum Vergleich:
`D:\rnf_re\out\dbobjects.dat`, `D:\rnf_re\out\dbtechtree_orig.dat`,
`tools\backup\dbButtons_orig.dat`. Zwischenstände in `tools\backup\`.

**Musik:** `Data\Music\Song1\Ambient01.mp3` wurde durch ein eigenes Stück
ersetzt. Das Spiel spielt gewöhnliche MP3s aus `Data\Music\Song1\`; welche
Datei wann läuft, steht in `db\dbmusic.dat` (37 Einträge à 216 Byte, Verweis
über den Dateinamen, **keine** Längenangabe). Beim Einsetzen eigener Stücke den
ID3-Block kurz halten — die Originaldateien haben 1 KB, eingebettete Cover
bringen schnell 100 KB mit. Original gesichert unter
`tools\backup\music\Ambient01_original.mp3`.

`dbmusic.dat`, Aufbau je Eintrag (216 Byte): `+0` laufende Nummer, `+4` Index,
`+8` Ordner (`Song1`), `+108` Dateiname, ab `+176` einzelne Bytes mit 0/1.
Darin **Zivilisations-Bytes**: `+198` Griechen, `+199` Perser, `+200` Rom,
`+205` Ägypten (belegt an den vier `…LevelUp.mp3`, die sich genau dort
unterscheiden). Alle Ambient- und Battle-Stücke haben alle vier gesetzt.
**`+208` / `+212` sind sehr wahrscheinlich ein Byte-Fenster in der MP3**
(Start/Ende bzw. Schleifenpunkt): bei allen 30 Ambient/Battle-Stücken liegt
`+212` unter der Dateigröße, meist bei 85–90 %; Siegesmusik und Jingles haben 0.
Für `Ambient01` steht dort noch das Fenster des alten 1,2-MB-Stücks
(416 … 1 083 540) — das neue, längere Stück würde demnach nach etwa 2:15
abbrechen.

**Aktuelle Ambient-Belegung (2026-09-14):** abwechselnd **8× „Sirens"**
(Ambient01, 03, 05 … 15) und **7× Max Richter „On the Nature of Daylight"**
(Ambient02, 04 … 14) — 15 Plätze, genaues 50/50 geht nicht.

**Vorher (vom Nutzer bestätigt):** „Sirens" auf allen 15 Plätzen
**lief im Spiel vollständig durch**.
Die lose `Data\db\dbmusic.dat` setzt dafür bei diesen 15 Einträgen das Fenster
auf `416 … Dateigröße − 8000` (≈ 1 s vor Schluss). Damit ist die Deutung von
`+208`/`+212` als Abspielfenster in Bytes **bestätigt**. Eine niedrigere
Bitrate (64 statt 128 kbit/s) stört das Spiel nicht. Die Battle-Plätze sind
noch original.

**`Victory.mp3`** (2026-09-14) durch *„The Odyssey Bgm … Sirens flute"* ersetzt
(1:18, ID3-Block von 193 KB entfernt). Das Fenster von `Victory` steht auf
`0..0` — solche Einträge (auch `Mourn01` und die vier Level-Up-Jingles) spielt
das Spiel ganz ab, dort wird nichts gesetzt. Original gesichert.

**Werkzeug `tools\rnf_music.pl <Ambient|Battle|Platzname> <Ordner oder Datei> [--dry-run]`:**
Platzname z. B. `Victory` oder `Mourn01` für einen einzelnen Eintrag. Prüft
jede MP3 auf Layer 3, schneidet ID3-Blöcke ab, verteilt die Dateien reihum auf
die Plätze der Kategorie (auch den unregelmäßig benannten `Battle7.mp3`),
sichert die Originale einmalig nach `tools\backup\music\` und setzt die Fenster.
Arbeitet auf der schon ausgelieferten `Data\db\dbmusic.dat` weiter.
**Nur MP3** — ein Encoder für andere Formate ist nicht vorhanden.

Zurücksetzen: alle `tools\backup\music\*_original.mp3` nach
`Data\Music\Song1\` zurückkopieren (Namen ohne `_original`) und
`Data\db\dbmusic.dat` löschen.

---

## 3. Was im Spiel funktioniert (vom Nutzer bestätigt)

* **Javelin Thrower ausbildbar** — Griechen in der Spartaner-Akademie, Perser in
  der Archery Range. Schaden auf 32 angehoben.
* **Bannerträger in allen vier Baracken ausbildbar**, mit dem Verhalten des
  Pädagogen: **+5 % Verstärkung im Umkreis von 10 m** (statt 3 m).
  Menüplätze: Griechen/Ägypten/Persien 11, Rom 12.
* **Römischer Streitwagen** im Stall (benutzt das ägyptische Modell, siehe unten).
* **Belagerungswaffen im Mauermenü**: Tower Catapult, Archimedes Claw, Naval
  Onager. Sie werden gebaut, stehen aber **neben** der Mauer, nicht darauf.
* **Behobene Menüfehler**: Bannerträger verdeckte das Schwert-Upgrade;
  Belagerungsplattform lag auf demselben Platz wie „Gate Right".

---

## 4. Was NICHT funktioniert — bitte nicht erneut versuchen

| Vorhaben | Ergebnis | Ursache, soweit bekannt |
|---|---|---|
| **Greek General ausbildbar machen** | erscheint nie, zwei Abstürze unterwegs | Sechs Bedingungen erfüllt (Bauliste, Preis, `t[1]`, `t[29]`, `+392`, `+596`/`+608`/`+768`), Datensatz byteweise ein Klon des Pädagogen — es muss eine siebte, unbekannte Bedingung geben |
| **Holzturm / Palisade ins Arbeitermenü** | erscheinen nie | Arbeitermenü ist mit Datenmitteln nicht erweiterbar; ausgeschlossen: Bauliste, alle 478 `dbobjects`-Felder, alle 44 Techtree-Felder, `dbButtons +216`, `dbcivspecificunitdefines` |
| **Belagerungsplattform baubar** | erscheint nie | unbekannt; Voraussetzungen und UI-Klasse sind in Ordnung |
| **Sichelwagen für die Griechen** | erscheint nicht, Perser unverändert | Das Spiel filtert nach Zivilisation, ein Zivilisationsfeld gibt es aber weder in `dbobjects` noch im Techtree (auch byteweise nicht). **Einheiten zwischen Völkern portieren geht nicht.** |
| **Aufwertung für Bannerträger/Javelin** | kein Aufwertungsfeld im Menü | Forschung umgewidmet, Einheit geklont, alles verdrahtet — trotzdem unsichtbar. Letzter Kontrollversuch wurde nicht mehr ausgewertet (siehe Abschnitt 9) |
| **Eigenes Banner je Volk** | unmöglich | Es existiert nur **ein** Fahnenträger-Modell (`men_yMflagbearer_02`) |
| **Römischer Streitwagen mit eigenem Modell** | unmöglich | Es gibt nur ein ägyptisches und ein persisches Streitwagenmodell |
| **Teamfarbe für Bannerträger/Javelin** | nicht per Daten | Ihre Texturen sind **DXT1**, ein Format ohne Alphakanal — und im Alpha steckt die Spielerfarbe. Nur durch Umwandeln nach DXT3 plus gemalter Maske zu beheben |
| **Spikes vom Arbeiter baubar** | nein | Familie 35 = „Ambient", also Deko statt Gebäude |

Früher widerlegte Theorien stehen ausführlich in `tools/FORMATS.md`, u. a.
„`f3/f4 = -1` entscheidet", „das Eltern-Feld ist die Freischaltung",
„`dbgraphics` ist 1:1 mit den Objekten", „die Kategorie-Tabelle ist die
Menüquelle".

---

## 5. Die wichtigsten gesicherten Formatfakten

`dbobjects.dat`: 3079 Records à 2012 Byte.

| Offset | Bedeutung |
|---|---|
| +104 | Familie (→ `dbfamily.dat`) |
| +120 / +196 | Trefferpunkte / Schaden |
| +296 | Namens-String-ID (→ `Language2.dll`) |
| +300 / +304 | Button / Grafik-Eintrag (→ `dbgraphics.dat`) |
| +392 | Ein/Aus: `-1` = an, `100000` = nie |
| +596 / +608 / +768 | „herstellbar"-Flags |
| +772 / +776 | zwei Flächeneffekt-Slots (→ `dbareaeffect.dat`) |
| +908 / +1212 | Bauliste: Anzahl / Einträge |
| +912 | eigene Objekt-ID |
| +1044…+1211 | eingebettete Kopie eines `dbspecialunittable`-Datensatzes (Sonderverhalten); darin `+108` Rate, `+112` Radius |

`dbtechtree.dat`: pro Einheit ein 44×u32-Eintrag, erkennbar an `[2] == 14`.
`[1]` = Stufe + 4, `[7]` Bauzeit, `[10]` Kosten, `[11]` Voraussetzung
(Forschungs-ID), `[16]` Button, `[18]` Name-String, `[29]` UI-Klasse.
Forschungen sind gleich aufgebaut, ihr Name steht in den 100 Byte **davor**,
danach zwei Listen mit vorangestellter Anzahl: Gebäude, die sie anbieten, und
was sie freischaltet.

`dbButtons.dat`: 2921 Records à 232 Byte. `+100` Icon-Pfad, `+204` eigener
Index, **`+216` Menüplatz**. Das Panel hat die Plätze 0–13 (im Code hart
geklemmt), obere Reihe 0–6 = Aufwertungen, untere 7–13 = Einheiten; Platz N und
N+7 liegen übereinander.

---

## 6. Werkzeuge (selbst geschrieben, in `tools\`)

| Skript | Zweck |
|---|---|
| `rnf_ssa3.pl` | Archiv `data.ssa` auflisten / entpacken (`cat <intern>` einzeln aufrufen) |
| `rnf_menu.pl` | Menü eines Gebäudes so anzeigen, wie das Spiel es auslegt — **vor jedem Menü-Patch benutzen** |
| `rnf_buildlist.pl` | Bauliste ändern (hält Zähler und Einträge synchron) |
| `rnf_buttonslot.pl` | Menüplatz eines Buttons setzen |
| `rnf_objpatch.pl` / `rnf_techpatch.pl` | einzelne Felder in Objekt- bzw. Techtree-Datensätzen |
| `rnf_clone.pl` | Datensatz klonen, Identität (`+100`, `+116`, `+300`, `+304`, `+912`) behalten |
| `rnf_split.pl` | Zweiseiten-Vergleich: welches Feld trennt zwei Gruppen von Objekten |
| `rnf_candidates.pl` | Kampagneneinheiten auflisten samt fehlender Bedingungen |
| `rnf_family.pl`, `rnf_special.pl`, `rnf_areaeffect.pl`, `rnf_civdefines.pl`, `rnf_gfxmodel.pl`, `rnf_dbdump.pl`, `rnf_findfield.pl`, `rnf_diffield.pl` | je eine Tabelle lesen oder ändern |

Ghidra: `D:\rnf_re\run_ghidra.sh <Skript.java> [Argumente] <Ausgabedatei>`.
Nützlich: `Dec.java` (dekompilieren), `FindCalls.java` (Aufrufer finden — eine
Byte-Suche scheitert, weil `call` relativ kodiert), `FindImm.java`,
`FindImmPair.java`, `RttiWalk.java`, `WhoOwns.java`, `Recover.java`.

---

## 7. Arbeitsregeln

1. **Das Spiel lässt sich von mir nicht starten und ansehen.** Jede Vermutung
   kostet den Nutzer einen Spielstart — also eine Änderung pro Test, und vorher
   alles rechnerisch prüfen, was sich prüfen lässt.
2. **Keine Fremdsoftware herunterladen oder ausführen** (Injektoren, Patcher).
   Lokal vorhanden und nutzbar: Ghidra, Perl, PowerShell, .NET, Java.
3. **Vor jedem Menü-Patch `rnf_menu.pl`** — ein Button gehört oft mehreren
   Objekten, und ein Platz muss in *jedem* Menü frei sein, in dem er vorkommt.
4. **Nur Plätze 0–13** vergeben.
5. **Vor jeder Änderung eine Sicherung** nach `tools\backup\`.
6. **Widerlegte Theorien dokumentieren**, nicht nur Erfolge.

---

## 8. Empfehlung für den nächsten Schritt

Der Mod ist an dem Punkt, wo die Engine Neues systematisch verweigert: neue
Einheiten, neue Menüeinträge, neue Aufwertungen. Sechs gefundene Bedingungen
haben nicht gereicht, und jeder Versuch kostet einen Spielstart.

**Vorschlag: neue Spielideen im Java-Projekt bauen** — nicht als vollständiger
Nachbau von Rise & Fall (das wäre Jahresarbeit), sondern als spielbarer
Ausschnitt. Der Vorteil ist nicht die Sprache, sondern die Rückmeldeschleife:
dort lässt sich kompilieren, starten, per `SceneSnapshot` ein Screenshot machen
und der eigene Fehler sofort sehen — ohne Testrunden beim Nutzer.

Vorgeschlagener erster Meilenstein:

1. Einheiten auswählen und bewegen
2. Kaserne, die ausbildet
3. Kampf mit Trefferpunkten
4. **Bannerträger mit Aura, Held mit Level, Aufwertung auf +10 % bei
   Heldenlevel 3 und +20 % bei Level 5, Stufe im Namen** — genau das Feature,
   das der Mod verweigert

Die Mod-Arbeit ist dabei die Grundlage: Modelle, Texturen, Spielerfarben und
Einheitenwerte lassen sich aus den Originaldateien laden.

**Stand 2026-09-12:** Die griechische Kaserne steht als echtes Modell im
Java-Projekt, und ein Klick darauf öffnet das Auswahl-HUD mit Porträt,
Lebensbalken, Namen und dem Kommandomenü. Das Menü wird *nicht* von Hand
gepflegt, sondern aus `dbobjects`/`dbButtons`/`dbtechtree` aufgebaut — die
Perl-Logik aus `tools/rnf_menu.pl` ist nach Java portiert (`com.rnf.db`).
Zwei Filter reichen, um aus 74 Baulisten-Einträgen die sieben zu machen, die
das Original zeigt: Techtree `[11] == 0` (Voraussetzung erfüllt) und der
Zivilisationsname im Entwicklernamen. Neu verstanden dabei:

* **`dbButtons +216 == 0` heisst „kein fester Platz", nicht „Platz 0".** Solche
  Einträge setzt die Engine selbst in die erste freie Zelle der passenden
  Reihe — genau so landet die Schwert-Aufwertung links oben über dem
  Schwertkämpfer. **Nur Aufwertungen** werden so gesetzt; Einheiten ohne
  festen Platz (z. B. `Building Defender Archer`) erscheinen gar nicht.
* **Forschungseinträge in `dbtechtree` sind an `[2] == 14` erkennbar wie
  Einheiten**, haben aber `[1] >= 6` statt `5` und `[17]/[19] != 1`.
* **`Language2.dll` ist eine normale Win32-Ressourcen-DLL.** Die Anzeigenamen
  (`dbobjects +296`) stehen als `RT_STRING` drin, 4631 Stück; ID 1038 =
  „Barracks". Kein Spielcode nötig, nur ein PE-Ressourcenlauf.
* **Die Spielerfarben-Maske gilt auch für Gebäude.** Bei der Kaserne decken
  sich die Alpha-Bereiche der Textur genau mit der Materialgruppe
  „PlayerColor" (Dachziegel und Zierband); der Rest ist deckend. Der
  Einheiten-Shader passt unverändert.

Danach: **Einheiten lassen sich ausbilden** und laufen aus dem Tor. Auch das
ohne handgepflegte Listen — die Kette vom Menüeintrag zum Modell ist

```
Bauliste-ID → dbobjects +304 → dbgraphics +100 → units\<name>.udf → models\*.gr2 + textures\*.dds
```

Weitere gesicherte Erkenntnisse dabei:

* **`dbgraphics +100` nennt die `.udf`, nicht das Modell.** Ein Sprung mehr
  als gedacht.
* **Die `.udf` ist zwar nicht vollständig entschlüsselt, aber ihre ersten
  Strings stehen in fester Reihenfolge:** `USTRB`, Objektname, `…MODEL…`,
  Textur. Das reicht, um Modell und Haut zu finden — und es ist nötig, weil
  die Namensregeln nicht tragen: `men_yMladderguy_MODEL_02` trägt die Textur
  `men_yMsiegecrew_02T`.
* **Techtree `[15]` ist der Record-Index in `dbobjects.dat`** (nicht die ID
  wie `[0]`). An allen vier ausbildbaren Kaserneneinheiten bestätigt; bisher
  stand dazu „unitspezifische ID, Bedeutung unklar".
* **Techtree `[7]` ist die Bau-/Ausbildungszeit, aber nicht in Sekunden.**
  Bürger 35, Kaserneninfanterie 45–55, Kavallerie 150, Turm 200. Die
  Verhältnisse stimmen, die Absolutwerte nicht — das Java-Projekt rechnet mit
  4 Ticks je Sekunde, was eine Annahme bleibt.
* **Die Anzeigenamen der griechischen Kaserneneinheiten** sind Hypaspist,
  Hoplite, Archer, Ladder Team (aus `Language2.dll`).

---

## 9. Offene Kleinigkeit

Beim letzten Kontrollversuch wurde die funktionierende Schwert-Aufwertung
testweise auf Platz 4 gelegt — dorthin, wo die neue Aufwertung unsichtbar
blieb. Das Ergebnis wurde nicht mehr abgefragt, der Versuch ist zurückgenommen.
Wer es wissen will: den Platz einer *funktionierenden* Forschung verschieben
und schauen, ob sie mitwandert. Wandert sie mit, liegt es an den Daten der
neuen Forschung; verschwindet sie, war es der Platz.
