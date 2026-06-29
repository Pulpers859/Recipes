import argparse
import base64
import json
import re
import uuid
from datetime import datetime, timezone
from html import unescape
from pathlib import Path


FRACTION_MAP = {
    "\u00bc": "1/4",
    "\u00bd": "1/2",
    "\u00be": "3/4",
    "\u2150": "1/7",
    "\u2151": "1/9",
    "\u2152": "1/10",
    "\u2153": "1/3",
    "\u2154": "2/3",
    "\u2155": "1/5",
    "\u2156": "2/5",
    "\u2157": "3/5",
    "\u2158": "4/5",
    "\u2159": "1/6",
    "\u215a": "5/6",
    "\u215b": "1/8",
    "\u215c": "3/8",
    "\u215d": "5/8",
    "\u215e": "7/8",
}


def iso8601_utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clean_text(text: str) -> str:
    text = unescape(text or "")
    text = text.replace("\xa0", " ")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def html_to_text(html_fragment: str) -> str:
    if not html_fragment:
        return ""
    text = html_fragment
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = clean_text(text)
    return text


def extract_meta_content(block: str, itemprop: str) -> str:
    patterns = [
        rf'<meta[^>]*itemprop="{re.escape(itemprop)}"[^>]*content="([^"]*)"',
        rf'<meta[^>]*content="([^"]*)"[^>]*itemprop="{re.escape(itemprop)}"',
    ]
    for pattern in patterns:
        match = re.search(pattern, block, flags=re.IGNORECASE)
        if match:
            return clean_text(match.group(1))
    return ""


def extract_itemprop_inner_text(block: str, itemprop: str) -> str:
    match = re.search(
        rf'<[^>]*itemprop="{re.escape(itemprop)}"[^>]*>(.*?)</[^>]+>',
        block,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not match:
        return ""
    return html_to_text(match.group(1))


def extract_source_url(block: str) -> str | None:
    # Prefer explicit anchor href inside recipeSource
    source_block = re.search(
        r'<[^>]*itemprop="recipeSource"[^>]*>(.*?)</[^>]+>',
        block,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not source_block:
        return None
    inner = source_block.group(1)
    href = re.search(r'href="([^"]+)"', inner, flags=re.IGNORECASE)
    if href:
        value = clean_text(href.group(1))
        return value or None
    text_value = html_to_text(inner)
    return text_value or None


def parse_minutes(value: str) -> int:
    value = clean_text(value).upper()
    if not value:
        return 0

    # ISO-8601 style durations like PT1H30M
    match = re.match(r"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$", value)
    if match:
        hours = int(match.group(1) or 0)
        minutes = int(match.group(2) or 0)
        seconds = int(match.group(3) or 0)
        return (hours * 60) + minutes + (1 if seconds >= 30 else 0)

    nums = [int(n) for n in re.findall(r"\d+", value)]
    if not nums:
        return 0
    return nums[0]


def parse_servings(serving_text: str) -> int:
    match = re.search(r"\d+", serving_text or "")
    if not match:
        return 1
    return max(int(match.group(0)), 1)


def normalize_fraction_chars(text: str) -> str:
    out = text
    for char, replacement in FRACTION_MAP.items():
        out = out.replace(char, replacement)
    return out


def parse_fraction(token: str) -> float:
    token = token.strip()
    if " " in token and "/" in token:
        whole, frac = token.split(" ", 1)
        return float(whole) + parse_fraction(frac)
    if "/" in token:
        a, b = token.split("/", 1)
        return float(a) / float(b)
    return float(token)


def parse_ingredient_line(raw: str) -> tuple[float, str, str]:
    text = normalize_fraction_chars(clean_text(raw))
    text = re.sub(r"^[\-\u2022]+\s*", "", text)
    text = re.sub(r"(?<=\d)(?=[A-Za-z])", " ", text)
    text = re.sub(r"(?<=/\d)(?=[A-Za-z])", " ", text)
    text = re.sub(r"\s+", " ", text).strip()

    # Pattern: "1 cup flour"
    full = re.match(r"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s+([A-Za-z%][A-Za-z%.-]*)\s+(.+)$", text)
    if full:
        amount_token, unit, name = full.groups()
        try:
            amount = parse_fraction(amount_token)
        except Exception:
            amount = 0.0
        return amount, unit.lower(), name.strip()

    # Pattern: "(1) 8-ounce block feta" -> amount=1, remainder as name
    paren = re.match(r"^\((\d+)\)\s+(.+)$", text)
    if paren:
        return float(paren.group(1)), "", paren.group(2).strip()

    # Pattern: "2 eggs" (amount + name)
    number_only = re.match(r"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s+(.+)$", text)
    if number_only:
        amount_token, name = number_only.groups()
        try:
            amount = parse_fraction(amount_token)
        except Exception:
            amount = 0.0
        return amount, "", name.strip()

    return 0.0, "", text


def extract_paragraphs_from_itemprop_div(block: str, itemprop: str) -> list[str]:
    section = re.search(
        rf'<div[^>]*itemprop="{re.escape(itemprop)}"[^>]*>(.*?)</div>',
        block,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not section:
        return []
    inner = section.group(1)
    paragraphs = re.findall(r"<p[^>]*>(.*?)</p>", inner, flags=re.IGNORECASE | re.DOTALL)
    if paragraphs:
        return [html_to_text(p) for p in paragraphs if html_to_text(p)]
    text = html_to_text(inner)
    return [line.strip() for line in text.split("\n") if line.strip()]


def map_category(course: str, category: str) -> str:
    combined = f"{course} {category}".lower()
    if "breakfast" in combined:
        return "breakfast"
    if "lunch" in combined:
        return "lunch"
    if "dinner" in combined or "entree" in combined or "main" in combined:
        return "dinner"
    if "appetizer" in combined or "starter" in combined:
        return "appetizer"
    if "snack" in combined:
        return "snack"
    if "dessert" in combined:
        return "dessert"
    if "beverage" in combined or "drink" in combined or "cocktail" in combined:
        return "beverage"
    if "sauce" in combined or "dressing" in combined:
        return "sauce"
    if "bread" in combined:
        return "bread"
    if "soup" in combined:
        return "soup"
    if "salad" in combined:
        return "salad"
    if "side" in combined:
        return "side"
    return "other"


def slugify_tag(text: str) -> str:
    tag = clean_text(text).lower()
    tag = re.sub(r"[^a-z0-9]+", "-", tag).strip("-")
    return tag


def collect_images_as_base64(block: str, source_root: Path) -> list[str]:
    srcs = re.findall(r'<img[^>]*src="([^"]+)"', block, flags=re.IGNORECASE)
    seen: set[str] = set()
    photo_data: list[str] = []

    for src in srcs:
        normalized = src.strip().replace("\\", "/")
        if not normalized.lower().startswith("images/"):
            continue
        if normalized in seen:
            continue
        seen.add(normalized)

        full_path = (source_root / normalized).resolve()
        if not str(full_path).startswith(str(source_root.resolve())):
            continue
        if not full_path.exists():
            continue

        raw = full_path.read_bytes()
        photo_data.append(base64.b64encode(raw).decode("ascii"))

    return photo_data


def parse_recipe_keeper_html(input_dir: Path) -> dict:
    html_path = input_dir / "recipes.html"
    if not html_path.exists():
        raise FileNotFoundError(f"Could not find recipes.html in {input_dir}")

    html_text = html_path.read_text(encoding="utf-8", errors="ignore")
    chunks = html_text.split('<div class="recipe-details">')
    blocks = chunks[1:]

    if not blocks:
        raise ValueError("No recipes were found in recipes.html")

    export_date = iso8601_utc_now()
    recipes: list[dict] = []

    for block in blocks:
        recipe_id = extract_meta_content(block, "recipeId")
        title = extract_itemprop_inner_text(block, "name")
        if not title:
            title = f"Recipe {len(recipes) + 1}"

        course = extract_itemprop_inner_text(block, "recipeCourse")
        category_text = extract_meta_content(block, "recipeCategory")
        source_url = extract_source_url(block)

        servings = parse_servings(extract_itemprop_inner_text(block, "recipeYield"))
        prep_time = parse_minutes(extract_meta_content(block, "prepTime"))
        cook_time = parse_minutes(extract_meta_content(block, "cookTime"))

        ingredients: list[dict] = []
        for ing_line in extract_paragraphs_from_itemprop_div(block, "recipeIngredients"):
            amount, unit, name = parse_ingredient_line(ing_line)
            if not name:
                continue
            ingredients.append(
                {
                    "id": str(uuid.uuid4()),
                    "name": name,
                    "amount": amount,
                    "unit": unit,
                    "section": "",
                    "isOptional": False,
                }
            )

        steps: list[dict] = []
        step_order = 1
        for step_line in extract_paragraphs_from_itemprop_div(block, "recipeDirections"):
            cleaned = re.sub(r"^\d+\s*[\.\)]\s*", "", step_line).strip()
            if not cleaned:
                continue
            steps.append(
                {
                    "id": str(uuid.uuid4()),
                    "order": step_order,
                    "instruction": cleaned,
                    "timerSeconds": None,
                    "timerLabel": None,
                }
            )
            step_order += 1

        notes_lines = extract_paragraphs_from_itemprop_div(block, "recipeNotes")
        notes = "\n".join(notes_lines).strip()

        rating_text = extract_meta_content(block, "recipeRating")
        rating = int(re.search(r"\d+", rating_text).group(0)) if re.search(r"\d+", rating_text) else 0
        rating = max(0, min(5, rating))

        favorite_text = extract_meta_content(block, "recipeIsFavourite").lower()
        is_favorite = favorite_text in {"true", "1", "yes"}

        tags = ["recipe-keeper-import"]
        category_tag = slugify_tag(category_text)
        if category_tag:
            tags.append(category_tag)
        course_tag = slugify_tag(course)
        if course_tag and course_tag not in tags:
            tags.append(course_tag)

        photo_data = collect_images_as_base64(block, input_dir)

        recipe = {
            "title": title,
            "summary": "",
            "ingredients": ingredients,
            "steps": steps,
            "servings": servings,
            "prepTime": prep_time,
            "cookTime": cook_time,
            "category": map_category(course, category_text),
            "tags": tags,
            "cuisine": "",
            "difficulty": "medium",
            "sourceURL": source_url,
            "sourceType": "url" if source_url else "manual",
            "notes": notes,
            "rating": rating,
            "isFavorite": is_favorite,
            "wantToTry": False,
            "photoData": photo_data,
            "dateLastCooked": None,
            "originalPDFData": None,
            "dateAdded": export_date,
            "timesCooked": 0,
            "_sourceRecipeId": recipe_id,
        }
        recipes.append(recipe)

    wrapper = {
        "version": 2,
        "exportDate": export_date,
        "recipeCount": len(recipes),
        "recipes": recipes,
    }
    return wrapper


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert Recipe Keeper HTML export into Recipe Vault JSON import format.")
    parser.add_argument("input_dir", type=Path, help="Directory containing recipes.html and images/")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("RecipeKeeper_RecipeVault_Import.json"),
        help="Output JSON file path",
    )
    args = parser.parse_args()

    result = parse_recipe_keeper_html(args.input_dir)

    # Remove helper field before writing output.
    for recipe in result["recipes"]:
        recipe.pop("_sourceRecipeId", None)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")

    image_total = sum(len(recipe.get("photoData", [])) for recipe in result["recipes"])
    print(f"Wrote {result['recipeCount']} recipes to: {args.output}")
    print(f"Embedded {image_total} total images into photoData")


if __name__ == "__main__":
    main()
