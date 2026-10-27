import re
from pathlib import Path

bib_path = Path("LaTex/referencias.bib")
bib = bib_path.read_text(encoding="utf-8")
entries = re.findall(r"@(\w+)\s*\{\s*([^,]+),([^@]+)", bib)
print(f"Total bib entries: {len(entries)}")

for idx, (etype, key, fields) in enumerate(entries, 1):
    m_title = re.search(r'title\s*=\s*[\"{](.+?)[\"}]', fields, re.DOTALL)
    m_year = re.search(r'year\s*=\s*[\"{](\d{4})[\"}]', fields)
    m_author = re.search(r'author\s*=\s*[\"{](.+?)[\"}]', fields, re.DOTALL)
    m_eprint = re.search(r'eprint\s*=\s*[\"{](.+?)[\"}]', fields)
    m_doi = re.search(r'doi\s*=\s*[\"{](.+?)[\"}]', fields)
    m_journal = re.search(r'(?:journal|booktitle)\s*=\s*[\"{](.+?)[\"}]', fields, re.DOTALL)

    t_str = m_title.group(1).replace("\n", " ").strip() if m_title else "No Title"
    y_str = m_year.group(1) if m_year else "No Year"
    a_str = m_author.group(1).split("and")[0].strip() if m_author else "No Author"
    j_str = m_journal.group(1).replace("\n", " ").strip() if m_journal else "No Venue"
    extra = f"arXiv:{m_eprint.group(1)}" if m_eprint else (f"DOI:{m_doi.group(1)}" if m_doi else "")
    print(f"[{idx:02d}] {key} ({y_str}): {a_str} et al. | {j_str[:35]} | {extra} | {t_str[:45]}...")
