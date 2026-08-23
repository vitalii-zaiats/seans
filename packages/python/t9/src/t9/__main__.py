"""``python -m t9 "FAMILY GUY"`` → ``326459 489``."""

import argparse
import sys
from collections.abc import Sequence

from t9.encode import digits, taps
from t9.layouts import LAYOUTS, Layout


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="t9", description=__doc__)
    parser.add_argument("text", nargs="*", help="the text; omitted, it is read from stdin")
    parser.add_argument(
        "-l",
        "--layout",
        choices=["auto", *LAYOUTS],
        default="auto",
        help="auto picks the keypad that knows the most of the text",
    )
    parser.add_argument("-t", "--taps", action="store_true", help="multi-tap, not one press")
    parser.add_argument("-s", "--sep", default="", help="between letters, with --taps")
    parser.add_argument(
        "--table",
        nargs="?",
        const="auto",
        choices=["auto", *LAYOUTS],
        help="print the keypad and stop; bare, it prints both",
    )
    return parser


def _table(layout: Layout) -> str:
    rows = (f"  {key.digit}  {' '.join(key.letters.upper())}" for key in layout.keys)
    return "\n".join([layout.name, *rows])


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)

    if args.table is not None:
        code = args.layout if args.table == "auto" else args.table
        wanted = LAYOUTS.values() if code == "auto" else [LAYOUTS[code]]
        print("\n\n".join(_table(layout) for layout in wanted))
        return 0

    text = " ".join(args.text) if args.text else sys.stdin.read().strip()
    layout = None if args.layout == "auto" else LAYOUTS[args.layout]
    print(taps(text, layout, sep=args.sep) if args.taps else digits(text, layout))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
