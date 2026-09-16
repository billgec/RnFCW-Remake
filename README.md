# Rise & Fall – Remake (Godot)

Privater Nachbau von *Rise & Fall: Civilizations at War* für macOS. Das Spiel läuft nativ in
Godot 4 (Metal). Grafiken, Modelle und Animationen stammen aus den Originaldaten und werden
von einem Konverter in offene Formate umgewandelt.

## Starten

```bash
./run.sh          # Spiel starten
./run.sh edit     # im Godot-Editor öffnen
./convert.sh      # Originaldaten neu konvertieren (nach Änderungen am Konverter)
```

Steuerung:

| Eingabe | Wirkung |
|---|---|
| WASD / Pfeiltasten / Maus am Rand | Kamera schieben |
| Mausrad · Q/E · mittlere Maustaste | Zoom · drehen |
| Linksklick / Rahmen ziehen | auswählen (Shift = hinzufügen) |
| Klick aufs Banner | ganze Gruppe auswählen |
| Rechtsklick | laufen · Gegner/Gebäude angreifen · Bürger: Gold/Holz sammeln, beim Bau helfen · Gebäude ausgewählt: Sammelpunkt |
| Cmd+Rechtsklick | Angriffsmarsch |
| Option (⌥) halten | Lebensbalken anzeigen |
| Leertaste · + / − · Tempo-Knöpfe oben | Pause · Spielgeschwindigkeit (0,5x bis 3x, jederzeit) |
| Doppelklick auf eine Einheit | alle sichtbaren Einheiten dieses Typs auswählen |
| Buttons unten rechts | Gebäude: Einheiten ausbilden · Bürger: Gebäude bauen (Linksklick setzen, Rechtsklick/Esc abbrechen) |

## Selbst am Code arbeiten

VS Code öffnen mit dem Ordner `remake` (Datei → Ordner öffnen) oder im Terminal:

```bash
open -a "Visual Studio Code" "/Users/billgec/Desktop/Code/Rise and Fall/remake"
```

Empfohlene Erweiterungen schlägt VS Code beim ersten Öffnen vor (`.vscode/extensions.json`):
**godot-tools** für GDScript und **Extension Pack for Java** für den Konverter.
Über Terminal → Task ausführen gibt es „Spiel starten", „Godot-Editor öffnen" und
„Assets konvertieren".

Wo was liegt: Spiellogik in `game/scripts/*.gd`, Balance in `game/data/bonuses.json`,
Shader in `game/shaders/`, Konverter in `converter/src/com/rnf/`.
Szenen und Materialien lassen sich im Godot-Editor bearbeiten (`./run.sh edit`).

## Aufbau

```
remake/
  converter/        Java: liest data.ssa, wandelt .gr2 -> glTF (Mesh, Skelett, Animationen)
                    und .dds -> PNG. Basis: das frühere RNFJava-Projekt (Archiv, Oodle-1, GR2).
  game/             Godot-Projekt
    assets/original/   vom Konverter erzeugt (nicht von Hand ändern)
    assets/overrides/  eigene Grafiken – haben Vorrang, siehe README dort
    scripts/           GDScript (assets.gd = Asset-Auflösung, unit.gd, selection_controller.gd …)
    shaders/           unit.gdshader (Spielerfarbe), terrain.gdshader
  docs/             FORMATS.md, REWRITE_OVERVIEW.md, HANDOVER.md (Reverse-Engineering-Wissen)
```

## Stand

- ✅ Archiv `data.ssa` direkt lesbar, Konverter-Pipeline
- ✅ Einheiten und Gebäude als skinned glTF inkl. aller Animationen der `.udf`
- ✅ Spielerfarbe über den Alphakanal, moderne Beleuchtung (Schatten, SSAO, SSIL, AgX)
- ✅ RTS-Kamera, Auswahl (Klick/Rahmen), Bewegungsbefehl in Formation, Lauf-/Ruheanimation
- ✅ Wegfindung (Navmesh, Gebäude ausgeschnitten)
- ✅ Kampf mit Originalwerten aus `dbobjects.dat` (HP, Schaden, Reichweite, Sicht, Tempo,
  Geschwindigkeit – Feldbedeutungen siehe `converter/src/com/rnf/db/UnitStats.java`),
  Nah- und Fernkampf mit Geschossen, Lebensbalken, Sterbe-/Totanimation, automatische Zielwahl
- ✅ Gefecht gegen den Computer: zwei Basen, Goldminen (Originalmodell), Wälder (Platzhalter-Bäume)
- ✅ Wirtschaft: Bürger sammeln Gold/Holz und bringen es zum Stadtzentrum, bauen Gebäude
- ✅ Ausbildung mit Original-Baulisten, -Icons, -Kosten und -Zeiten (`civs/greek.json`)
- ✅ HUD: Ressourcen, Auswahl (Porträt, HP, Gruppenübersicht), Befehlsraster, Warteschlange
- ✅ Gruppen ab 9 gleichen Soldaten mit dem Original-Formationsbanner; ein Klick auf ein
  Mitglied oder das Banner wählt die ganze Gruppe, neue Einheiten schließen sich an
- ✅ Original-Mauszeiger je nach Situation (Angriff, Holz, Gold, Bauen, Reparieren, Sammelpunkt)
- ✅ Klassenboni über `data/bonuses.json` (Speer gegen Reiter usw.), frei änderbar
- ✅ Gebäude: Siedlung, Stadtzentrum, Kaserne, Schießplatz, Stall, Spartanerakademie, Turm
  (schießt), Markt, Regierungszentrum – mit den Voraussetzungen aus dem Techtree
- ✅ Bürger reparieren beschädigte Gebäude
- ✅ Sammelpunkt mit der lila Original-Fahne (samt Weh-Animation), sichtbar bei ausgewähltem Gebäude
- ✅ Ausbildung in Gruppen: mindestens 3 Soldaten pro Auftrag, je Siedlung einer mehr (max. 6);
  Bürger und Belagerungsgerät einzeln
- ✅ Computergegner: sammelt, bildet aus, greift in Wellen an (erste nach 7 Minuten)
- ⏳ Aufwertungen, Rüstungswerte, schöneres HUD, Heldenmodus, Gelände/Karten, weitere Völker

Bäume: CC0-Paket „Stylized Nature MegaKit" von Quaternius unter `game/assets/nature`
(Lizenz liegt dort bei). Die Originalbäume sind SpeedTree-Dateien (`.spt`) und damit
prozedurale Beschreibungen statt Modelle – die lassen sich nicht direkt konvertieren.

Screenshots: `docs/screenshots/`.
