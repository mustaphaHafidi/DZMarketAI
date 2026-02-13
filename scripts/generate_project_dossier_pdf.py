#!/usr/bin/env python3
"""Generate a stakeholder-ready PDF from the project dossier markdown.

Usage:
  python scripts/generate_project_dossier_pdf.py
  python scripts/generate_project_dossier_pdf.py --input docs/DZMarket_Dossier_Projet_FR.md --output docs/DZMarket_Dossier_Projet_FR.pdf
"""

from __future__ import annotations

import argparse
import html
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
)


def build_styles():
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="Body",
            parent=styles["Normal"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=14,
            spaceAfter=4,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H1",
            parent=styles["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=colors.HexColor("#0d3f2f"),
            spaceAfter=8,
            spaceBefore=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H2",
            parent=styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=13,
            leading=17,
            textColor=colors.HexColor("#1a5a45"),
            spaceAfter=6,
            spaceBefore=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H3",
            parent=styles["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=11.5,
            leading=15,
            textColor=colors.HexColor("#2b6e56"),
            spaceAfter=4,
            spaceBefore=4,
        )
    )
    return styles


def as_paragraph(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(html.escape(text), style)


def parse_markdown_to_story(content: str):
    styles = build_styles()
    story = []
    bullet_buffer = []
    number_buffer = []

    def flush_bullets():
        nonlocal bullet_buffer
        if not bullet_buffer:
            return
        items = [ListItem(as_paragraph(item, styles["Body"])) for item in bullet_buffer]
        story.append(
            ListFlowable(
                items,
                bulletType="bullet",
                start="circle",
                bulletFontName="Helvetica",
                bulletFontSize=8,
                leftPadding=14,
                spaceAfter=6,
            )
        )
        bullet_buffer = []

    def flush_numbers():
        nonlocal number_buffer
        if not number_buffer:
            return
        items = [ListItem(as_paragraph(item, styles["Body"])) for item in number_buffer]
        story.append(
            ListFlowable(
                items,
                bulletType="1",
                leftPadding=14,
                spaceAfter=6,
            )
        )
        number_buffer = []

    for raw_line in content.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if not stripped:
            flush_bullets()
            flush_numbers()
            story.append(Spacer(1, 3))
            continue

        if stripped == "<!-- PAGE_BREAK -->":
            flush_bullets()
            flush_numbers()
            story.append(PageBreak())
            continue

        if stripped.startswith("# "):
            flush_bullets()
            flush_numbers()
            story.append(as_paragraph(stripped[2:].strip(), styles["H1"]))
            continue

        if stripped.startswith("## "):
            flush_bullets()
            flush_numbers()
            story.append(as_paragraph(stripped[3:].strip(), styles["H2"]))
            continue

        if stripped.startswith("### "):
            flush_bullets()
            flush_numbers()
            story.append(as_paragraph(stripped[4:].strip(), styles["H3"]))
            continue

        if stripped.startswith("- "):
            flush_numbers()
            bullet_buffer.append(stripped[2:].strip())
            continue

        # Keep simple numbered lists "1. item"
        if (
            len(stripped) > 3
            and stripped[0].isdigit()
            and "." in stripped[:4]
            and stripped.split(".", 1)[1].strip()
        ):
            prefix, rest = stripped.split(".", 1)
            if prefix.isdigit():
                flush_bullets()
                number_buffer.append(rest.strip())
                continue

        flush_bullets()
        flush_numbers()
        story.append(as_paragraph(stripped, styles["Body"]))

    flush_bullets()
    flush_numbers()
    return story


def generate_pdf(input_path: Path, output_path: Path) -> None:
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    content = input_path.read_text(encoding="utf-8")
    story = parse_markdown_to_story(content)

    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title="DZMarket - Dossier Projet",
        author="DZMarket",
    )
    doc.build(story)


def main():
    parser = argparse.ArgumentParser(description="Generate project dossier PDF from markdown.")
    parser.add_argument(
        "--input",
        default="docs/DZMarket_Dossier_Projet_FR.md",
        help="Input markdown path",
    )
    parser.add_argument(
        "--output",
        default="docs/DZMarket_Dossier_Projet_FR.pdf",
        help="Output PDF path",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    generate_pdf(input_path, output_path)
    print(f"PDF generated: {output_path}")


if __name__ == "__main__":
    main()
