# -*- coding: utf-8 -*-
"""Verify bibliographic metadata against Crossref (DOI) and arXiv (preprints).

Usage:
    python verificar_referencias.py dois     -> resolve every DOI in DOIS
    python verificar_referencias.py query    -> free-text Crossref search for QUERIES
    python verificar_referencias.py arxiv    -> arXiv ID lookup / search
Outputs JSON lines to stdout and caches results in ../refs_cache.json
"""
import json
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

UA = {"User-Agent": "ODC-Artigo05/1.0 (mailto:dafnhe.thor@msn.com)"}
CACHE = Path(__file__).resolve().parent.parent / "refs_cache.json"

DOIS = sys.argv[2:] if len(sys.argv) > 2 and sys.argv[1] == "dois" else []


def get(url, accept="application/json"):
    req = urllib.request.Request(url, headers={**UA, "Accept": accept})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")


def summarize(m):
    authors = "; ".join(
        f"{a.get('family','')}, {a.get('given','')}" for a in m.get("author", [])
    )
    year = None
    for k in ("published-print", "published-online", "issued"):
        if m.get(k, {}).get("date-parts"):
            year = m[k]["date-parts"][0][0]
            break
    return {
        "doi": m.get("DOI"),
        "type": m.get("type"),
        "title": (m.get("title") or [""])[0],
        "container": (m.get("container-title") or [""])[0],
        "volume": m.get("volume"),
        "issue": m.get("issue"),
        "pages": m.get("page") or m.get("article-number"),
        "year": year,
        "publisher": m.get("publisher"),
        "authors": authors,
    }


def by_doi(doi):
    url = "https://api.crossref.org/works/" + urllib.parse.quote(doi)
    try:
        return summarize(json.loads(get(url))["message"])
    except Exception as e:  # noqa: BLE001
        return {"doi": doi, "error": str(e)}


def by_query(q, rows=3):
    url = "https://api.crossref.org/works?rows=%d&query.bibliographic=%s" % (
        rows,
        urllib.parse.quote(q),
    )
    try:
        items = json.loads(get(url))["message"]["items"]
        return [summarize(i) for i in items]
    except Exception as e:  # noqa: BLE001
        return [{"query": q, "error": str(e)}]


def arxiv(query=None, ids=None, maxr=5):
    if ids:
        url = "http://export.arxiv.org/api/query?id_list=" + ",".join(ids)
    else:
        url = "http://export.arxiv.org/api/query?max_results=%d&search_query=%s" % (
            maxr,
            urllib.parse.quote(query),
        )
    ns = {"a": "http://www.w3.org/2005/Atom"}
    root = ET.fromstring(get(url, "application/atom+xml"))
    out = []
    for e in root.findall("a:entry", ns):
        out.append(
            {
                "id": e.findtext("a:id", namespaces=ns),
                "title": " ".join(e.findtext("a:title", namespaces=ns).split()),
                "published": e.findtext("a:published", namespaces=ns),
                "authors": "; ".join(
                    a.findtext("a:name", namespaces=ns)
                    for a in e.findall("a:author", ns)
                ),
            }
        )
    return out


if __name__ == "__main__":
    mode = sys.argv[1]
    cache = json.loads(CACHE.read_text("utf-8")) if CACHE.exists() else {}
    if mode == "dois":
        for d in sys.argv[2:]:
            r = by_doi(d)
            cache[d] = r
            print(json.dumps(r, ensure_ascii=False))
            time.sleep(0.2)
    elif mode == "query":
        for q in sys.argv[2:]:
            print("### " + q)
            for r in by_query(q):
                print("   " + json.dumps(r, ensure_ascii=False))
            time.sleep(0.2)
    elif mode == "arxivid":
        for r in arxiv(ids=sys.argv[2:]):
            print(json.dumps(r, ensure_ascii=False))
    elif mode == "arxivq":
        for q in sys.argv[2:]:
            print("### " + q)
            for r in arxiv(query=q):
                print("   " + json.dumps(r, ensure_ascii=False))
            time.sleep(3)
    CACHE.write_text(json.dumps(cache, indent=1, ensure_ascii=False), "utf-8")
