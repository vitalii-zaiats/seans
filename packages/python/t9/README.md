# t9

Text to the digits you'd press on a phone keypad.

```python
from t9 import digits, taps

digits("FAMILY GUY")   # "326459 489"
digits("ГРІФІНИ")      # "2647454"
taps("GUY")            # "488999" — every press, as on a phone with no dictionary
```

```
$ python -m t9 "FAMILY GUY"
326459 489
$ python -m t9 --table uk
```

`digits` presses each key once and leaves the ambiguity in, which is what T9
itself sends: the dictionary on the phone is what turned `4663` back into
`home`. `taps` is the older way — hold down until the letter you want comes up.

The keypad is guessed from the text: whichever of the two knows more of its
letters. Pass `layout=LATIN` or `layout=UKRAINIAN` when you'd rather say.
Anything not on the keypad — spaces, punctuation, digits, a letter from the
other alphabet — comes through unchanged, or `unknown="drop"` / `"strict"`.

## The keypads

| key | latin  | ukrainian |
|-----|--------|-----------|
| 2   | `abc`  | `абвгґ`   |
| 3   | `def`  | `деєжз`   |
| 4   | `ghi`  | `иіїйк`   |
| 5   | `jkl`  | `лмно`    |
| 6   | `mno`  | `прст`    |
| 7   | `pqrs` | `уфхцч`   |
| 8   | `tuv`  | `шщь`     |
| 9   | `wxyz` | `юя`      |

The Latin one is ITU E.161 and there is only one of it. **There is no Ukrainian
standard.** What phones shipped was the Russian keypad — `абвг` / `дежз` /
`ийкл` / … — with `ё ъ ы э` removed and `ґ є і ї` put back in alphabetical
order, all 33 letters over eight keys, which is the table above. If the one you
remember split them elsewhere, a `Layout` is a name and eight `Key`s:

```python
from t9 import Key, Layout, digits

mine = Layout(name="mine", keys=(Key("2", "абвг"), ...))
digits("ГРІФІНИ", layout=mine)
```

## Indexing a catalogue

`Index` turns a list of titles into the digit sequences that find them, and
answers a prefix in microseconds. It has no dependencies and no database
underneath — 6 000 titles are 36 000 codes and about ten megabytes.

```python
from t9 import Entry, Index

index = Index.of(
    Entry(ref=card.slug, names=(card.name, card.original_name), rank=card.imdb_mark or 0)
    for card in catalogue
)

for hit in index.find("489", limit=12):     # 4-8-9, "GUY"
    print(hit.entry.ref)
```

Three things make it work on a remote:

- **Every word start is its own code.** `489` finds "Family Guy" without typing
  the first word — which also means `0` is never needed as a separator, and a
  title written `Поганці мусять помирати / Погані хлопці мають померти` is
  findable from either half without anybody splitting it.
- **A title is indexed under all its names**, each with the keypad its own
  script needs, chosen per word. `2647454` (Ґріфіни) and `326459` (Family) land
  on the same slug.
- **A name the query spells out in full outranks a longer one that merely
  starts with it.** Rank alone buries the title somebody typed completely under
  whatever blockbuster shares its first digits.

`rank` is yours: an IMDb score, a view count, recency. Bigger wins.

### What it costs, measured

5 904 titles from the live catalogue, 36 471 codes, built in 130 ms. The
question is how many keys somebody presses before the title they meant is on
the screen — twelve results shown, the Ukrainian title typed from its start:

| keys pressed | 3 | 4 | 5 | 8 |
|--------------|---|---|---|---|
| title on screen | 12% | 51% | **86%** | 99% |

Median five presses; typing a word from the middle of the title instead, four.
0.0% of titles never surface. Latency per keystroke, over the whole catalogue:

| digits typed | 1 | 2 | 3 | 4 | 5 |
|--------------|---|---|---|---|---|
| `find()`     | 2 ms | 510 µs | 56 µs | 9 µs | 3 µs |

One digit is worth skipping — it scans a third of the index to rank it, and
narrows nothing. Two is where searching starts paying.

For comparison, the same title on the app's D-pad grid: four characters cost
**22 presses** on average, because every letter is a walk across seventy keys.
