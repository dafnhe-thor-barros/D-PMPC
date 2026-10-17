#!/usr/bin/env python3
# -*- coding: utf-8 -*-

extra = """
@book{patel2005spacecraft,
  author    = {Patel, Mukund R.},
  title     = {Spacecraft Power Systems},
  publisher = {CRC Press},
  pages     = {1--491},
  year      = {2005},
  doi       = {10.1201/9781420038484}
}

@article{walker1984satellite,
  author    = {Walker, John G.},
  title     = {Satellite Constellations},
  journal   = {Journal of the British Interplanetary Society},
  volume    = {37},
  number    = {12},
  pages     = {559--572},
  year      = {1984}
}

@book{wertz2011space,
  author    = {Wertz, James R. and Everett, David F. and Puschell, Jeffery J.},
  title     = {Space Mission Engineering: The New SMAD},
  publisher = {Microcosm Press / Springer},
  pages     = {1--1033},
  year      = {2011}
}
"""

with open(r"C:\ZZ - Antigravity\Mestrado\01 - Artigos\Artigo 05\LaTex\referencias.bib", "a", encoding="utf-8") as f:
    f.write(extra)

print("Appended 3 classic entries to referencias.bib successfully.")
