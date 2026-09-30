# Arbetsorder

Den här filen är målet. Människan skriver rader under **Kö**; PO tar dem i ordning, en i taget,
när ingen story är i arbete, och skriver varje rad som en story i `.team/backlog/`.

Regler:
- En rad = en story = en PR. Är raden för stor delar PO den i flera stories och bockar raden när alla är skrivna.
- PO bockar raden (`- [x]`) och skriver story-ID:t sist på raden.
- Oklar rad: PO frågar människan i sin ruta och går vidare med nästa rad som är klar.
- Beroenden: skriv `(efter NNN)` på raden; PO parkerar storyn som `_NNN-slug.md` med raden `parked-until: NNN` tills NNN är mergad.
- En rad som ändrar regelboken (AGENTS.md, .team/team.md, REVIEW.md, .team/roles/) säger det uttryckligen.

## Kö

## Väntar på människan

## Operatör

PO skriver hit när en mergad PR kräver något bara människan får göra (hemlighet, driftsättning, migrering,
infrastruktur, spend, beslut). Människan tar bort raden när det är gjort.
