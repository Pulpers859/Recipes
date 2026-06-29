import argparse
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from pypdf import PdfReader


CATEGORY_LABELS = {
    "BREAKFAST": "breakfast",
    "LUNCH & DINNER": "dinner",
    "SNACKS & APPS": "snack",
    "SNACKS": "snack",
    "APPETIZERS": "appetizer",
    "DESSERT": "dessert",
    "DESSERTS": "dessert",
}

STOP_LINES = {
    "BACK TO CONTENTS",
}

TITLE_NOISE_LINES = {
    "CARBS",
    "FAT",
    "PROTEIN",
    "INGREDIENTS",
    "INSTRUCTIONS",
    "NOTES",
}

META_PREFIXES = (
    "MACROS:",
    "CALORIES:",
    "SERVINGS:",
    "PREP:",
    "COOK:",
    "TOTAL",
    "ADDITIONAL:",
)

LOWERCASE_WORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "of",
    "on",
    "or",
    "the",
    "to",
    "w/",
    "w/o",
    "with",
}

UPPERCASE_WORDS = {
    "bbq",
    "pb",
    "usa",
}


def clean_line(line: str) -> str:
    line = line.replace("\xa0", " ")
    line = re.sub(r"\s+", " ", line).strip()
    return line


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\xa0", " ")
    return text


def detect_recipe_starts(page_texts: list[str]) -> list[int]:
    starts: list[int] = []
    for i, page in enumerate(page_texts):
        if re.search(r"(?im)^Ingredients\s*$", page) and re.search(r"(?i)MACROS\s*:", page):
            starts.append(i)
    return starts


def parse_int_from_text(text: str, default: int = 0) -> int:
    match = re.search(r"\d+", text)
    return int(match.group(0)) if match else default


def parse_minutes(text: str) -> int:
    text = text or ""
    nums = [int(n) for n in re.findall(r"\d+", text)]
    if not nums:
        return 0
    if "-" in text and len(nums) >= 2:
        return round((nums[0] + nums[1]) / 2)
    return nums[0]


def parse_fraction(token: str) -> float:
    token = token.strip()
    if " " in token and "/" in token:
        whole, frac = token.split(" ", 1)
        return float(whole) + parse_fraction(frac)
    if "/" in token:
        a, b = token.split("/", 1)
        return float(a) / float(b)
    return float(token)


def is_mostly_uppercase(text: str) -> bool:
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return False
    upper_count = sum(1 for c in letters if c.isupper())
    return (upper_count / len(letters)) >= 0.75


def smart_title_case(text: str) -> str:
    raw = clean_line(text)
    if not raw:
        return raw

    # Keep mixed/lowercase strings as-is to avoid mangling brands and existing casing.
    if not is_mostly_uppercase(raw):
        return raw

    tokens = re.split(r"(\s+)", raw)
    converted: list[str] = []
    word_index = 0

    for token in tokens:
        if not token or token.isspace():
            converted.append(token)
            continue

        prefix = re.match(r"^[\(\[\{\"'`]+", token)
        suffix = re.search(r"[\)\]\}\"'`.,:;!?]+$", token)
        pre = prefix.group(0) if prefix else ""
        suf = suffix.group(0) if suffix else ""
        core = token[len(pre) : len(token) - len(suf) if suf else len(token)]

        if not core:
            converted.append(token)
            continue

        lowered = core.lower()
        if lowered in UPPERCASE_WORDS:
            cased = lowered.upper()
        elif word_index > 0 and lowered in LOWERCASE_WORDS:
            cased = lowered
        elif re.search(r"\d", core):
            cased = lowered
        else:
            cased = lowered.capitalize()

        # Keep contractions and possessives readable (e.g., "king's").
        cased = re.sub(r"([A-Za-z])'([A-Za-z])", lambda m: f"{m.group(1)}'{m.group(2).lower()}", cased)

        converted.append(f"{pre}{cased}{suf}")
        word_index += 1

    result = "".join(converted)
    result = re.sub(r"\bw/\s+o\b", "w/o", result, flags=re.IGNORECASE)
    return clean_line(result)


def parse_amount_unit_name(raw: str) -> tuple[float, str, str]:
    text = clean_line(raw)
    text = re.sub(r"(?<=\d)(?=[A-Za-z])", " ", text)

    mixed = re.match(r"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s+([A-Za-z%][A-Za-z%.-]*)\s+(.+)$", text)
    if mixed:
        amount_token, unit, name = mixed.groups()
        try:
            amount = parse_fraction(amount_token)
        except Exception:
            amount = 0.0
        return amount, unit.lower(), smart_title_case(name)

    number_only = re.match(r"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s+(.+)$", text)
    if number_only:
        amount_token, name = number_only.groups()
        try:
            amount = parse_fraction(amount_token)
        except Exception:
            amount = 0.0
        return amount, "", smart_title_case(name)

    return 0.0, "", smart_title_case(text)


def clean_title(raw_title: str) -> str:
    title = clean_line(raw_title)
    title = re.sub(r"^\+\d+(?:\.\d+)?g?\s*", "", title, flags=re.IGNORECASE)
    title = re.sub(r"^[A-Z]{2,}\s+[A-Z]{2,}(?=[A-Z][a-z])", "", title)
    title = re.sub(r"^[A-Z]{2,}(?=[A-Z][a-z])", "", title)
    title = re.sub(r"(\w)-\s+(\w)", r"\1-\2", title)
    title = re.sub(r"\b([A-Z])\s+([a-z]{2,})\b", r"\1\2", title)
    title = re.sub(r"w/\s+o\b", "w/o", title, flags=re.IGNORECASE)
    title = re.sub(
        r"\s+(BREAKFAST|LUNCH\s*&\s*DINNER|SNACKS?\s*&\s*APPS?|APPETIZERS?|DESSERTS?)$",
        "",
        title,
        flags=re.IGNORECASE,
    )
    return smart_title_case(title)


def is_author_line(line: str) -> bool:
    cl = clean_line(line)
    if not cl or ":" in cl:
        return False
    return re.fullmatch(r"[A-Z]{2,}(?:\s+[A-Z]{2,}){0,2}", cl) is not None


def should_skip_title_line(line: str) -> bool:
    cl = clean_line(line)
    if not cl:
        return True

    upper = cl.upper()
    if cl == upper and upper in CATEGORY_LABELS:
        return True
    if upper in STOP_LINES:
        return True
    if cl == upper and upper in TITLE_NOISE_LINES:
        return True
    if re.fullmatch(r"\+\d+(?:\.\d+)?G?", upper):
        return True
    if cl.startswith("@"):
        return True
    if re.fullmatch(r"\d+", cl):
        return True
    if upper.startswith(META_PREFIXES):
        return True
    return False


def parse_title_and_category(
    title_candidate_lines: list[str], all_start_lines: list[str], chunk_text: str, recipe_index: int
) -> tuple[str, str]:
    category = "other"
    title_lines: list[str] = []

    for line in all_start_lines:
        cl = clean_line(line)
        if not cl:
            continue

        upper = cl.upper()
        if cl == upper and upper in CATEGORY_LABELS:
            category = CATEGORY_LABELS[upper]

    for line in title_candidate_lines:
        cl = clean_line(line)
        if should_skip_title_line(cl):
            continue
        title_lines.append(cl)

    if not title_lines:
        for i, line in enumerate(all_start_lines):
            if "BACK TO CONTENTS" not in line.upper():
                continue
            fallback: list[str] = []
            for next_line in all_start_lines[i + 1 :]:
                cl = clean_line(next_line)
                if not cl:
                    continue
                if cl.startswith("@"):
                    break
                if is_author_line(cl):
                    if fallback:
                        break
                    continue
                if should_skip_title_line(cl):
                    continue
                fallback.append(cl)
            if fallback:
                title_lines = fallback
                break

    if not title_lines:
        for raw_line in normalize_text(chunk_text).split("\n"):
            cl = clean_line(raw_line)
            upper = cl.upper()
            if not cl:
                continue
            if category != "other":
                category_keys = [k for k, v in CATEGORY_LABELS.items() if v == category]
            else:
                category_keys = list(CATEGORY_LABELS.keys())
            matched = next((k for k in category_keys if k in upper and len(cl) > len(k) + 3), None)
            if matched:
                prefix = cl[: upper.find(matched)]
                cleaned = clean_title(prefix)
                if cleaned and not should_skip_title_line(cleaned):
                    title_lines = [cleaned]
                    break

    if not title_lines:
        title = f"Imported Recipe {recipe_index}"
    else:
        title = clean_title(" ".join(title_lines))

    if not title:
        title = f"Imported Recipe {recipe_index}"

    return title, category


def extract_field(text: str, label: str) -> str:
    pattern = rf"(?im)^{re.escape(label)}\s*:\s*(.+)$"
    match = re.search(pattern, text)
    return clean_line(match.group(1)) if match else ""


def parse_ingredients(start_page_text: str) -> list[dict]:
    lines = [clean_line(l) for l in normalize_text(start_page_text).split("\n")]

    try:
        ing_idx = next(i for i, l in enumerate(lines) if l.lower() == "ingredients")
    except StopIteration:
        return []

    try:
        instr_idx = next(i for i, l in enumerate(lines[ing_idx + 1 :], start=ing_idx + 1) if l.lower() == "instructions")
    except StopIteration:
        instr_idx = len(lines)

    ingredient_lines: list[str] = []
    for line in lines[ing_idx + 1 : instr_idx]:
        upper = line.upper()
        if not line:
            continue
        if upper in STOP_LINES:
            continue
        if line.startswith("@"):
            continue
        if line == upper and upper in CATEGORY_LABELS:
            continue
        if re.fullmatch(r"\d+", line):
            continue
        if line == upper and upper in TITLE_NOISE_LINES:
            continue
        if re.fullmatch(r"\+\d+(?:\.\d+)?G?", upper):
            continue
        if upper.startswith(META_PREFIXES):
            continue
        if is_author_line(line):
            continue
        if line:
            ingredient_lines.append(line)

    parsed: list[dict] = []
    current_section = ""
    pending_bullet = False

    for line in ingredient_lines:
        if line == "•":
            pending_bullet = True
            continue

        is_section = line.endswith(":") and not line.startswith("•") and len(line) <= 80
        if is_section:
            current_section = line[:-1].strip().title()
            continue

        if line.startswith("•") or pending_bullet:
            item = line.lstrip("•").strip() if line.startswith("•") else line
            pending_bullet = False
            if not item:
                continue
            parsed.append({"raw": item, "section": current_section})
            continue

        if parsed:
            parsed[-1]["raw"] = f"{parsed[-1]['raw']} {line}".strip()
        else:
            parsed.append({"raw": line, "section": current_section})

    result: list[dict] = []
    for item in parsed:
        amount, unit, name = parse_amount_unit_name(item["raw"])
        result.append(
            {
                "id": str(uuid.uuid4()),
                "name": name,
                "amount": amount,
                "unit": unit,
                "section": item["section"],
                "isOptional": False,
            }
        )

    return result


def parse_steps_and_notes(chunk_text: str) -> tuple[list[dict], str]:
    lines = [clean_line(l) for l in normalize_text(chunk_text).split("\n") if clean_line(l)]
    lower_lines = [l.lower() for l in lines]

    try:
        start_idx = next(i for i, l in enumerate(lower_lines) if l == "instructions")
    except StopIteration:
        return [], ""

    mode = "instructions"
    instruction_lines: list[str] = []
    notes_lines: list[str] = []

    for line in lines[start_idx + 1 :]:
        upper = line.upper()

        if upper == "NOTES":
            mode = "notes"
            continue

        if upper in STOP_LINES or "BACK TO CONTENTS" in upper:
            if instruction_lines or notes_lines:
                break
            continue

        if line.startswith("@"):
            if instruction_lines or notes_lines:
                break
            continue

        if line == upper and upper in TITLE_NOISE_LINES:
            continue
        if line == upper and upper in CATEGORY_LABELS:
            continue
        if re.fullmatch(r"\+\d+(?:\.\d+)?G?", upper):
            continue
        if re.fullmatch(r"\d+", line):
            continue
        if is_author_line(line):
            if instruction_lines or notes_lines:
                break
            continue

        if mode == "instructions":
            instruction_lines.append(line)
        else:
            notes_lines.append(line)

    steps: list[str] = []
    current = ""

    for line in instruction_lines:
        step_match = re.match(r"^(\d+)\.\s*(.*)$", line)
        if step_match:
            if current:
                steps.append(current.strip())
            current = step_match.group(2).strip()
            continue

        if current:
            current = f"{current} {line}".strip()
        else:
            current = line

    if current:
        steps.append(current.strip())

    step_objs = [
        {
            "id": str(uuid.uuid4()),
            "order": i + 1,
            "instruction": re.sub(r"\s+", " ", step).strip(),
            "timerSeconds": None,
            "timerLabel": None,
        }
        for i, step in enumerate(steps)
        if step
    ]

    notes = "\n".join(notes_lines).strip()
    return step_objs, notes


def parse_recipe(start_page_text: str, chunk_text: str, recipe_index: int) -> dict:
    start_lines = [clean_line(l) for l in normalize_text(start_page_text).split("\n")]

    try:
        ing_idx = next(i for i, l in enumerate(start_lines) if l.lower() == "ingredients")
        title_lines = start_lines[:ing_idx]
    except StopIteration:
        title_lines = start_lines[:8]

    title, category = parse_title_and_category(title_lines, start_lines, chunk_text, recipe_index)

    servings_text = extract_field(start_page_text, "SERVINGS")
    prep_text = extract_field(start_page_text, "PREP")
    cook_text = extract_field(start_page_text, "COOK")
    macros_text = extract_field(start_page_text, "MACROS")
    calories_text = extract_field(start_page_text, "CALORIES")

    servings = max(parse_int_from_text(servings_text, default=1), 1)
    prep_time = parse_minutes(prep_text)
    cook_time = parse_minutes(cook_text)

    ingredients = parse_ingredients(start_page_text)
    steps, notes_text = parse_steps_and_notes(chunk_text)

    note_parts = []
    if macros_text:
        note_parts.append(f"Macros: {macros_text}")
    if calories_text:
        note_parts.append(f"Calories: {calories_text}")
    if notes_text:
        note_parts.append(notes_text)

    notes = "\n".join(note_parts).strip()

    if not steps:
        steps = [
            {
                "id": str(uuid.uuid4()),
                "order": 1,
                "instruction": "Review source PDF page and add instructions manually.",
                "timerSeconds": None,
                "timerLabel": None,
            }
        ]

    if not ingredients:
        ingredients = [
            {
                "id": str(uuid.uuid4()),
                "name": "Review source PDF page and add ingredients manually",
                "amount": 0,
                "unit": "",
                "section": "",
                "isOptional": False,
            }
        ]

    return {
        "title": title,
        "summary": "",
        "ingredients": ingredients,
        "steps": steps,
        "servings": servings,
        "prepTime": prep_time,
        "cookTime": cook_time,
        "category": category,
        "tags": ["counter-cookbook"],
        "cuisine": "",
        "difficulty": "medium",
        "sourceURL": None,
        "sourceType": "pdf",
        "notes": notes,
        "rating": 0,
        "isFavorite": False,
        "wantToTry": False,
        "photoData": [],
        "dateLastCooked": None,
        "originalPDFData": None,
        "dateAdded": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "timesCooked": 0,
    }


def extract_recipes(pdf_path: Path) -> list[dict]:
    reader = PdfReader(str(pdf_path))
    page_texts = [normalize_text(page.extract_text() or "") for page in reader.pages]

    starts = detect_recipe_starts(page_texts)
    if not starts:
        raise RuntimeError("No recipe starts found. PDF may not be text-readable.")

    recipes: list[dict] = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(page_texts)
        chunk = "\n\n".join(page_texts[start:end])
        recipe = parse_recipe(page_texts[start], chunk, i + 1)
        recipes.append(recipe)

    return recipes


def build_export_wrapper(recipes: list[dict]) -> dict:
    return {
        "version": 2,
        "exportDate": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "recipeCount": len(recipes),
        "recipes": recipes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract Counter Cookbook recipes into RecipeVault JSON backup format.")
    parser.add_argument(
        "--pdf",
        required=True,
        help="Path to source PDF (e.g. Counter_Cookbook.pdf)",
    )
    parser.add_argument(
        "--out",
        default="Counter_Cookbook_RecipeVault_Import.json",
        help="Output JSON path",
    )
    args = parser.parse_args()

    pdf_path = Path(args.pdf)
    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")

    recipes = extract_recipes(pdf_path)
    payload = build_export_wrapper(recipes)

    out_path = Path(args.out)
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"Extracted {len(recipes)} recipes")
    print(f"Output: {out_path.resolve()}")


if __name__ == "__main__":
    main()
