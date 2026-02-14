# m.sh
# m — MySQL CLI helper for quick table browsing

`m` is a small Bash script to speed up day-to-day inspection and maintenance of a MySQL database from the terminal.  
It was made to be fast to use without mouse: list tables with numbers, then refer to a table by **name or number**.

By default it uses the database:

- **DB:** `mydatabase`

It also auto-switches to vertical output (`\G`) when a table is “wide” (many columns), so results stay readable.

---

## Features

- List tables **numbered** (cache-based, fast to select by number)
- `SELECT * ... LIMIT N` with optional forced vertical output (`v`)
- `tail` mode (latest rows, auto-detect order column: `id` → `created_at` → `updated_at`)
- `tail auto` monitor mode (refresh every 2s)
- `DESCRIBE`, `COUNT(*)`
- Dangerous ops with confirmation (`DROP`, `DELETE by id`, `TRUNCATE`)
- Run arbitrary SQL (`m sql "..."`)
- Quick filtering with `WHERE` (`m <table> filter "<where>"`)

---

## Requirements

- Bash
- `mysql` CLI client available in PATH
- Permission to connect to the database `mydatabase` (the script just runs `mysql mydatabase -e "..."`)

> Tip: your MySQL credentials can come from `~/.my.cnf`, env vars, or whatever you already use with `mysql`.

---

## Install

Put the script somewhere in your PATH and name it `m`:

```bash
chmod +x m
sudo mv m /usr/local/bin/m

type m --help 
