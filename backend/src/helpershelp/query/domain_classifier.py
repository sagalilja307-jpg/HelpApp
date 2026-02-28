from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Tuple, cast

from helpershelp.query.intent_plan import Domain
from helpershelp.llm import get_embedding_service


@dataclass(frozen=True)
class DomainResult:
    domain: Domain | None
    confidence: float
    ranked: List[Tuple[Domain, float]]
    needs_clarification: bool
    suggestions: List[Domain]


class DomainClassifier:
    """
    Embedding-only domain classifier.

    - min_confidence: below => needs_clarification
    - min_margin: if top1 - top2 < margin => needs_clarification
    """

    def __init__(
        self,
        *,
        min_confidence: float = 0.55,
        min_margin: float = 0.06,
    ):
        self._embed = get_embedding_service()
        self.min_confidence = min_confidence
        self.min_margin = min_margin

        # Guardrails: queries that often get misclassified but are out-of-scope for your domains.
        self._out_of_scope_keywords = {
            "personnummer",
            "bank",
            "bankid",
            "bank-id",
            "lösenord",
            "password",
            "pin",
            "pinkod",
            "kortnummer",
            "kreditkort",
            "skatt",
            "deklaration",
            "ssn",
        }

        self._domain_cards: Dict[Domain, str] = {
            "calendar": (
                "Domän: kalender. Händelser, möten, bokningar, agenda, tider, heldag.\n"
                "Typiska frågor:\n"
                "Vad har jag inplanerat idag?\n"
                "När börjar mitt nästa möte?\n"
                "Hur många aktiviteter har jag den här veckan?\n"
                "När är mitt första möte imorgon?\n"
                "Vad händer?\n"
                "Vad är på gång?\n"
                "Hur ser det ut?\n"
                "Är det något idag?\n"
                "Är jag upptagen?\n"
                "Har jag något sen?\n"
                "Vad har jag framför mig?\n"
                "Är det lugnt?\n"
                "Vad har jag den här tiden?\n"
                "Är det något jag missar?\n"
                "Vilka tider är lediga på fredag?\n"
                "Hur länge är mötet med [person]?\n"
                "Har jag något bokat på söndag?\n"
                "Vilka aktiviteter är markerade som heldag?\n"
                "När är nästa gång jag träffar [person]?\n"
                "Hur många möten har jag före kl. 12 idag?\n"
                "Nyckelord: möte, bokat, inplanerat, kalender, aktivitet, agenda, heldag."
            ),
            "mail": (
                "Domän: mejl. Inkorg, avsändare, ämne, olästa, svara, bilagor, viktiga.\n"
                "Typiska frågor:\n"
                "Hur många olästa mejl har jag?\n"
                "Har jag fått mejl från [person] idag?\n"
                "När kom det senaste mejlet?\n"
                "Hur många mejl fick jag igår?\n"
                "Har jag några mejl med bilagor?\n"
                "Vilka mejl är markerade som viktiga?\n"
                "Har jag obesvarade mejl i inkorgen?\n"
                "När svarade jag senast på ett mejl?\n"
                "Finns det mejl med ämnet \"[ord]\"?\n"
                "Har jag fått mejl efter kl. 20 idag?\n"
                "Nyckelord: mejl, mail, inkorg, olästa, bilaga, viktigt, obesvarade, ämne."
            ),
            "reminders": (
                "Domän: påminnelser/uppgifter/todos. Att-göra, deadlines, förfallodatum, klara, försenade.\n"
                "Typiska frågor:\n"
                "Hur många påminnelser har jag idag?\n"
                "Vilka påminnelser förfaller imorgon?\n"
                "Har jag några försenade uppgifter?\n"
                "När är nästa påminnelse planerad?\n"
                "Hur många uppgifter är markerade som klara den här veckan?\n"
                "Har jag några uppgifter utan förfallodatum?\n"
                "Vilka uppgifter ligger i listan \"[namn]\"?\n"
                "Finns det påminnelser schemalagda i helgen?\n"
                "Hur många uppgifter har jag totalt just nu?\n"
                "Har jag några återkommande påminnelser?\n"
                "Nyckelord: påminnelse, uppgift, todo, att göra, deadline, förfaller, försenad, klar."
            ),
            "notes": (
                "Domän: anteckningar/noter. Textanteckningar, mappar, nyligen, innehåll.\n"
                "Typiska frågor:\n"
                "Hur många anteckningar har jag totalt?\n"
                "När skapade jag min senaste anteckning?\n"
                "Vilka anteckningar ändrades den här veckan?\n"
                "Finns det anteckningar som innehåller ordet \"[ord]\"?\n"
                "Vilka anteckningar har jag öppnat nyligen?\n"
                "Har jag några anteckningar utan titel?\n"
                "Vilken är min äldsta anteckning?\n"
                "Hur många anteckningar skapade jag den senaste månaden?\n"
                "Finns det anteckningar med bilagor eller bilder?\n"
                "Vilka anteckningar ligger i mappen \"[namn]\"?\n"
                "Nyckelord: anteckning, notes, text, mapp, öppnat, ändrades, bilaga, titel."
            ),
            "memory": (
                "Domän: minne/memory. Sammanfattningar av vad jag gjort, nyckelhändelser, mönster över tid.\n"
                "Typiska frågor:\n"
                "Vad minns jag från förra veckan?\n"
                "Vad har jag gjort den senaste månaden?\n"
                "Vad brukar jag göra på morgonen?\n"
                "Vilka återkommande mönster ser du i min historik?\n"
                "Har jag gjort något relaterat till [ämne] nyligen?\n"
                "Nyckelord: minne, minnen, memory, historik, mönster, sammanfattning, kom ihåg."
            ),
            "health": (
                "Domän: hälsa/health. Aktivitet, steg, träning, sömn, puls, HRV, andning, blodsyre, mående.\n"
                "Typiska frågor:\n"
                "Hur många steg tog jag igår?\n"
                "Hur långt gick jag förra veckan?\n"
                "Hur sov jag inatt?\n"
                "Hur var min puls idag?\n"
                "Har jag tränat den här veckan?\n"
                "Nyckelord: hälsa, steg, träning, workout, sömn, puls, HRV, blodsyre, andning."
            ),
            "files": (
                "Domän: filer/dokument. Dokument, mappar, metadata (skapad/ändrad/storlek), sök på namn.\n"
                "Typiska frågor:\n"
                "Vilka dokument har jag öppnat idag?\n"
                "När ändrades filen \"[filnamn]\" senast?\n"
                "Hur många filer finns i mappen \"[namn]\"?\n"
                "Har jag laddat ner några nya filer den här veckan?\n"
                "Vilka filer har jag öppnat flest gånger senaste månaden?\n"
                "Finns det dokument större än 50 MB?\n"
                "Vilka filer innehåller ordet \"[ord]\" i namnet?\n"
                "När skapades dokumentet \"[filnamn]\"?\n"
                "Har jag några filer jag inte öppnat på över ett år?\n"
                "Vilka filer har jag importerat via dokumentväljaren?\n"
                "Nyckelord: fil, dokument, pdf, mapp, öppna, ladda ner, importera, storlek."
            ),
            "location": (
                "Domän: plats/position. Besökta platser, var jag var, tid på plats, senaste plats.\n"
                "Typiska frågor:\n"
                "Var befinner jag mig just nu?\n"
                "Vilka platser har jag besökt idag?\n"
                "När var jag senast på \"[plats]\"?\n"
                "Hur länge var jag på jobbet igår?\n"
                "Vilka platser besökte jag förra veckan?\n"
                "Hur många olika platser har jag varit på den här månaden?\n"
                "När lämnade jag hemmet idag?\n"
                "Har jag varit på \"[plats]\" fler än en gång den här veckan?\n"
                "Hur lång tid tog det att resa till jobbet idag?\n"
                "Vilken plats besökte jag senast?\n"
                "Nyckelord: plats, position, var, besökt, resa, hem, jobb, kontor."
            ),
            "photos": (
                "Domän: bilder/foton. Bilder, videor, album, favoriter, metadata (datum/plats).\n"
                "Typiska frågor:\n"
                "Hur många bilder har jag tagit idag?\n"
                "När tog jag den senaste bilden?\n"
                "Hur många bilder tog jag förra veckan?\n"
                "Finns det bilder från \"[datum]\"?\n"
                "Vilka bilder är markerade som favoriter?\n"
                "Hur många videor har jag spelat in den här månaden?\n"
                "Finns det bilder tagna på \"[plats]\"?\n"
                "Hur många bilder finns i albumet \"[namn]\"?\n"
                "När togs den äldsta bilden i mitt bibliotek?\n"
                "Har jag importerat några nya bilder den här veckan?\n"
                "Nyckelord: bild, foto, bilder, video, album, favorit, kamerarulle, import."
            ),
            "contacts": (
                "Domän: kontakter. Personer, telefonnummer, e-post, dubletter, saknade fält.\n"
                "Typiska frågor:\n"
                "Hur många kontakter har jag totalt?\n"
                "Har jag en kontakt sparad för \"[namn]\"?\n"
                "När lades kontakten \"[namn]\" till?\n"
                "Vilka kontakter saknar telefonnummer?\n"
                "Vilka kontakter saknar e-postadress?\n"
                "Finns det dubletter bland mina kontakter?\n"
                "Vilka kontakter har företag angivet?\n"
                "Hur många kontakter har jag lagt till den här månaden?\n"
                "Vilka kontakter är markerade som favoriter?\n"
                "Vad är telefonnumret eller e-postadressen till \"[namn]\"?\n"
                "Nyckelord: kontakt, telefonnummer, e-post, adressbok, person, dublett."
            ),
        }

    def classify(self, query: str) -> DomainResult:
        q = (query or "").strip()
        if not q:
            return DomainResult(
                domain=None,
                confidence=0.0,
                ranked=[],
                needs_clarification=True,
                suggestions=[],
            )

        lower = q.lower()
        forced_clarification = any(k in lower for k in self._out_of_scope_keywords)

        # Quick explicit keyword matching before running embeddings.
        # This handles high-confidence intent keywords and short queries.
        explicit_map: Dict[Domain, List[str]] = {
            "calendar": ["kalender", "möte", "möten", "händelse", "bokning", "agenda"],
            "mail": ["mejl", "mail", "inkorg", "epost", "e-post"],
            "reminders": ["påminn", "påminnelse", "uppgift", "uppgifter", "todo", "att göra"],
            "notes": ["anteckning", "anteckningar", "notes", "notering"],
            "memory": ["minne", "minnen", "memory", "historik", "mönster", "kom ihåg", "remember"],
            "health": [
                "hälsa",
                "health",
                "steg",
                "sömn",
                "sovit",
                "puls",
                "vilopuls",
                "hrv",
                "blodsyre",
                "andning",
                "träning",
                "tränat",
                "workout",
                "exercise",
                "mindful",
                "sinnestillstånd",
            ],
            "files": ["fil", "filer", "dokument", "pdf", "mapp"],
            "photos": ["bild", "bilder", "foto", "foton", "album", "video", "videor"],
            "contacts": ["kontakt", "kontakter", "telefonnummer", "adressbok"],
            "location": ["plats", "position", "var är jag", "var var jag", "besökt", "resa"],
        }

        for domain, keys in explicit_map.items():
            if any(k in lower for k in keys):
                return DomainResult(
                    domain=domain,
                    confidence=1.0,
                    ranked=[(domain, 1.0)],
                    needs_clarification=False,
                    suggestions=[],
                )

        candidates: List[Tuple[Domain, str]] = list(self._domain_cards.items())
        texts = [card for _, card in candidates]
        card_to_domain = {card: domain for domain, card in candidates}

        ranked_text = self._embed.similarity_batch(q, texts)

        ranked: List[Tuple[Domain, float]] = []
        for text, score in ranked_text:
            domain = card_to_domain.get(text)
            if domain is None:
                continue
            ranked.append((cast(Domain, domain), float(score)))

        if not ranked:
            # extremely defensive fallback
            return DomainResult(
                domain=None,
                confidence=0.0,
                ranked=[],
                needs_clarification=True,
                suggestions=cast(List[Domain], list(self._domain_cards.keys())[:3]),
            )

        ranked.sort(key=lambda x: x[1], reverse=True)

        top_domain, top_score = ranked[0]
        second_score = ranked[1][1] if len(ranked) > 1 else -1.0
        margin = top_score - second_score

        needs = forced_clarification or (top_score < self.min_confidence) or (margin < self.min_margin)
        suggestions = [d for d, _ in ranked[:3]] if needs else []

        return DomainResult(
            domain=None if needs else top_domain,
            confidence=top_score,
            ranked=ranked,
            needs_clarification=needs,
            suggestions=cast(List[Domain], suggestions),
        )
