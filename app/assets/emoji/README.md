# Bundled Owner Emoji

The complete ordered emoji catalogue (including skin tones, ZWJ sequences and
flags) comes from Emojibase 17.0.0, with Russian CLDR labels and Russian/English
search keywords. Graphics are unmodified Twemoji 17.0.3 SVGs. Standalone
non-emoji building blocks without a group/order are not selectable identities.

- Graphics: https://github.com/jdecked/twemoji/tree/v17.0.3 (CC BY 4.0).
  Copyright Twitter, Inc. and other contributors. See TWEMOJI-LICENSE.txt.
- Data: https://github.com/milesj/emojibase (MIT, copyright Miles Johnson).
  See EMOJIBASE-LICENSE.txt.

Regenerate from the repository root with `python scripts/update-emoji-assets.py`.
The script also generates the backend allowlist; update both in the same change.
All images and search data are bundled and work offline without a font/CDN.

`icon_key` uses `emoji:` followed by the Unicode emoji, which fits the existing
24-character PostgreSQL column even for the longest supported sequences.
Legacy boy/girl/person/family keys remain readable and map to emoji graphics.
