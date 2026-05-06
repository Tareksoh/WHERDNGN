"""Extract Arabic Baloot PDFs from Downloads to UTF-8 text files in
.swarm_findings/_pdf_extracted/. pymupdf handles Arabic far better
than pypdf (correct character ordering, no presentation-forms).

Run once before audit agents are dispatched.
"""
import os
import sys
import unicodedata
import fitz  # pymupdf

DOWNLOADS = r"C:\Users\USER\Downloads"
OUTDIR = r"C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted"

PDFS = [
    ("01_registration_system",     "Copy of نظام التسجيل في البلوت.pdf"),
    ("02_playing_system",          "نظام اللعب في البلوت.pdf"),
    ("03_secrets_pro_1",           "سر الاحتراف في لعبة البلوت١.pdf"),
    ("04_secrets_pro_3",           "سر الاحتراف في لعبة البلوت ٣.pdf"),
    ("05_what_is_baloot",          "ماهو البلوت في لعبة البلوت.pdf"),
    ("06_third",                   "الثالث.pdf"),
    ("07_doubling_system",         "نظام الدبل في لعبة البلوت.pdf"),
]


def normalize_arabic(text: str) -> str:
    """Convert Arabic Presentation Forms (FE70-FEFF, FB50-FDFF) back to
    canonical Arabic letters via NFKC. Drop zero-width joiners that
    pypdf-style extracts often inject between every glyph.
    """
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    # ZWJ / ZWNJ between every char is common in PDF text streams; drop.
    text = text.replace("‌", "").replace("‍", "")
    return text


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    log = []
    for slug, fname in PDFS:
        src = os.path.join(DOWNLOADS, fname)
        dst = os.path.join(OUTDIR, f"{slug}.txt")
        if not os.path.exists(src):
            log.append(f"MISSING: {fname}")
            continue
        try:
            doc = fitz.open(src)
            chunks = [f"# Source: {fname}\n# Slug:   {slug}\n# Pages:  {len(doc)}\n\n"]
            for i, page in enumerate(doc, 1):
                t = normalize_arabic(page.get_text("text") or "")
                chunks.append(f"\n--- page {i} ---\n{t}\n")
            doc.close()
            with open(dst, "w", encoding="utf-8") as f:
                f.write("".join(chunks))
            size = os.path.getsize(dst)
            log.append(f"OK: {slug} ({size}b)")
        except Exception as e:
            log.append(f"ERROR {slug}: {e}")
    with open(os.path.join(OUTDIR, "_log.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(log))
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("\n".join(log))


if __name__ == "__main__":
    main()
