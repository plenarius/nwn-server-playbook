# A custom content repository, to start from

Copy this folder to make the repository for your haks and your talk table. Chapter 7 of the guide walks through it.

| Path | What it is |
|---|---|
| `haks/<name>/` | One folder per hak. Every file in it, and in its subfolders, goes into `<name>.hak` |
| `tlk/<name>.tlk.json` | Your talk table as text. It becomes `<name>.tlk` |
| `build.sh` | Builds everything into `build/hak` and `build/tlk` |
| `.gitignore` | Keeps built files out of git |

`haks/my_first_hak` and `tlk/my_tlk.tlk.json` are tiny examples for the chapter's walk-through. Replace them with
your own content.

Names of haks and talk tables: at most 16 lowercase letters, digits and underscores. Names of files inside a hak:
at most 16 characters before the extension. `build.sh` checks both.
