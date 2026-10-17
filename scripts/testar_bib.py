import re
import urllib.request
import json
import time

bib_path = r"C:\ZZ - Antigravity\Mestrado\01 - Artigos\Artigo 05\LaTex\referencias.bib"
bib = open(bib_path, encoding='utf-8').read()
entries = re.findall(r'@\w+\s*\{\s*([^,]+),[\s\S]*?doi\s*=\s*[\"{]([^\"}]+)[\"}][\s\S]*?\}', bib)

print(f"Found {len(entries)} entries with DOIs")
valid = []
invalid = []

for key, d in entries:
    url = f"https://api.crossref.org/works/{d}"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'BibChecker/1.0 (mailto:test@example.com)'})
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))['message']
            title = (data.get('title') or [''])[0]
            print(f"[OK] {key} -> {d} | {title[:50]}")
            valid.append((key, d, title))
    except Exception as e:
        print(f"[FAIL] {key} -> {d} | Error: {e}")
        invalid.append((key, d, str(e)))
    time.sleep(0.1)

print("\n--- Summary ---")
print(f"Valid DOIs: {len(valid)}")
print(f"Invalid DOIs: {len(invalid)}")
