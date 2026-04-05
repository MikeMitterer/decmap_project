# Infos zu Files

Alle Files wurden mit Claude-Cowork erstellt.
Konvertierung von SVG zu PNG mit `svg2png.txt`

## Aktuelle Assets

| Datei | Verwendung |
|---|---|
| `decisionmap-logo-gradient-light.svg/.png` | Header — heller Modus |
| `decisionmap-logo-gradient-dark.svg/.png` | Header — dunkler Modus |
| `decisionmap-icon-gradient.svg/.png` | App-Icon (quadratisch) |
| `decisionmap-favicon-gradient.svg/.png` | Browser-Tab |
| `directus-project-logo.svg/.png` | Directus Admin-Panel Logo |
| `directus-login-background.svg/.png` | Directus Login-Hintergrund |

## SVG-Technik

- Kein `<rect>`-Hintergrund → vollständig transparent
- Pin-Cutouts (Kreise + Linien) via `<mask>` implementiert → echte transparente Löcher, funktionieren auf jedem Hintergrund
- Gradient Orange→Lila in beiden Varianten identisch; Unterschied: Kontrast der Schrift/Pin-Elemente
