#!/bin/bash
set -euo pipefail

DEFAULT_LIMIT=20
WIDE_COL_THRESHOLD=8
CACHE_DIR="${HOME:-/tmp}"
CONFIG_FILE="${CACHE_DIR}/.m_db"
FIXED_DB="$(cat "$CONFIG_FILE" 2>/dev/null || true)"
FIXED_DB="${FIXED_DB//[$'\r\n']/}"
DB="${M_DB:-${FIXED_DB:-nrgestorbackend}}"
CACHE_FILE="${CACHE_DIR}/.m_tables_cache_${DB}"

usage() {
  cat <<'EOF'
Uso:
  -d <banco> | --db <banco> -> usa o banco <banco> só neste comando
                              (padrão: banco fixado, $M_DB ou nrgestorbackend)
                              vale no início de qualquer comando abaixo
  -D | --databases          -> lista os bancos disponíveis (SHOW DATABASES)
  -D <banco>                -> igual a -d <banco>
  -D <banco> fix            -> fixa <banco> como padrão para os próximos comandos

  m                      -> SHOW TABLES numerado (use o numero como tabela)
  m <tabela|n>            -> SELECT * FROM <tabela> LIMIT 20 (auto \G se larga)
  m <tabela|n> <n>        -> SELECT * FROM <tabela> LIMIT <n> (auto \G se larga)
  m <tabela|n> v          -> SELECT * FROM <tabela> LIMIT 20  (força \G)
  m <tabela|n> <n> v      -> SELECT * FROM <tabela> LIMIT <n> (força \G)
  m t <tabela|n> [n] [v]  -> últimos registros (ORDER BY id/created_at/updated_at DESC)
  m t <tabela|n> auto [n] [v] -> monitora últimos registros (CTRL+C para sair)

  m fix                    -> fixa o banco atual como padrão
  m fix clear              -> remove o banco fixado

  m desc|d <tabela|n>     -> DESCRIBE <tabela>
  m count|c <tabela|n>    -> SELECT COUNT(*) FROM <tabela>
  m drop|dr <tabela|n>    -> DROP TABLE <tabela> (confirmação)
  m del|dl <tabela|n> <id> -> DELETE FROM <tabela> WHERE id = <id> (confirmação)
  m empty|e <tabela|n>    -> TRUNCATE TABLE <tabela> (confirmação)
  m <tabela|n> filter|f <WHERE> [v] -> SELECT * FROM <tabela> WHERE <WHERE> LIMIT 20
  m sql|s "<SQL>"        -> Executa SQL livre
EOF
}

is_number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

run_mysql() {
  mysql "$DB" -e "$1"
}

list_tables() {
  mysql -N -B "$DB" -e "SHOW TABLES;"
}

save_table_cache() {
  list_tables > "$CACHE_FILE"
}

resolve_table_arg() {
  local arg="$1"
  if ! is_number "$arg"; then
    echo "$arg"
    return
  fi
  if [ ! -f "$CACHE_FILE" ]; then
    save_table_cache
  fi
  local table
  table="$(sed -n "${arg}p" "$CACHE_FILE")"
  if [ -z "$table" ]; then
    echo "Número inválido. Rode 'm' para listar as tabelas." >&2
    exit 1
  fi
  echo "$table"
}

get_column_count() {
  mysql -N -B "$DB" -e "
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = '$DB'
      AND table_name = '$1';
  "
}

column_exists() {
  mysql -N -B "$DB" -e "
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = '$DB'
      AND table_name = '$1'
      AND column_name = '$2';
  "
}

resolve_tail_order() {
  local table="$1"
  if [ "$(column_exists "$table" "id")" -gt 0 ]; then
    echo "id"
    return
  fi
  if [ "$(column_exists "$table" "created_at")" -gt 0 ]; then
    echo "created_at"
    return
  fi
  if [ "$(column_exists "$table" "updated_at")" -gt 0 ]; then
    echo "updated_at"
    return
  fi
  echo ""
}

clear_screen() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf "\033c"
  fi
}

confirm() {
  local msg="$1"
  echo "⚠️  $msg"
  read -r -p "Digite YES para confirmar: " confirm
  [ "$confirm" = "YES" ] || { echo "Operação cancelada."; exit 1; }
}

# --- main ---
while [ "${1:-}" = "-d" ] || [ "${1:-}" = "--db" ] || [ "${1:-}" = "-D" ] || [ "${1:-}" = "--databases" ]; do
  if [ "$1" = "-D" ] || [ "$1" = "--databases" ]; then
    if [ "${2:-}" = "" ]; then
      mysql -N -B -e "SHOW DATABASES;" | while IFS= read -r name; do
        if [ -n "$FIXED_DB" ] && [ "$name" = "$FIXED_DB" ]; then
          printf '%s (fixado)\n' "$name"
        elif [ "$name" = "$DB" ]; then
          printf '%s (padrão)\n' "$name"
        else
          printf '%s\n' "$name"
        fi
      done
      exit 0
    fi
    [ "$2" = "fix" ] && { shift 1; continue; }
  fi
  [ "${2:-}" = "" ] && { echo "Informe o banco após $1."; exit 1; }
  DB="$2"
  shift 2
done
CACHE_FILE="${CACHE_DIR}/.m_tables_cache_${DB}"

if [ "${1:-}" = "" ]; then
  save_table_cache
  nl -w2 -s'. ' "$CACHE_FILE"
  exit 0
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  fix)
    if [ "${2:-}" = "clear" ]; then
      rm -f "$CONFIG_FILE"
      echo "Banco fixado removido. O padrão volta a ser nrgestorbackend (ou \$M_DB)."
    elif [ "${2:-}" != "" ]; then
      echo "Uso: m fix | m -d <banco> fix | m -D <banco> fix | m fix clear"
      exit 1
    elif mysql -N -B -e "SHOW DATABASES;" | grep -Fqx "$DB"; then
      printf '%s\n' "$DB" > "$CONFIG_FILE"
      echo "Banco '$DB' fixado como padrão (salvo em $CONFIG_FILE)."
    else
      echo "Erro: banco '$DB' não existe." >&2
      exit 1
    fi
    ;;
  d|desc)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    TABLE="$(resolve_table_arg "$2")"
    run_mysql "DESCRIBE \`$TABLE\`;"
    ;;
  c|count)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    TABLE="$(resolve_table_arg "$2")"
    run_mysql "SELECT COUNT(*) AS total FROM \`$TABLE\`;"
    ;;
  dr|drop)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    TABLE="$(resolve_table_arg "$2")"
    confirm "Isso vai apagar DEFINITIVAMENTE a tabela '$TABLE'."
    run_mysql "DROP TABLE \`$TABLE\`;"
    echo "Tabela '$TABLE' removida."
    ;;
  dl|del)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    [ "${3:-}" = "" ] && { echo "Informe o id."; exit 1; }
    is_number "$3" || { echo "ID precisa ser numérico."; exit 1; }

    TABLE="$(resolve_table_arg "$2")"
    confirm "Isso vai apagar o registro id=$3 da tabela '$TABLE'."
    run_mysql "DELETE FROM \`$TABLE\` WHERE id = $3 LIMIT 1;"
    echo "Registro id=$3 removido de '$TABLE'."
    ;;
  e|empty)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    TABLE="$(resolve_table_arg "$2")"
    confirm "Isso vai remover TODOS os registros da tabela '$TABLE' (TRUNCATE)."
    run_mysql "TRUNCATE TABLE \`$TABLE\`;"
    echo "Tabela '$TABLE' esvaziada."
    ;;
  s|sql)
    [ "${2:-}" = "" ] && { echo "Informe o SQL."; exit 1; }
    shift
    run_mysql "$*"
    ;;
  t)
    [ "${2:-}" = "" ] && { echo "Informe a tabela."; exit 1; }
    TABLE="$(resolve_table_arg "$2")"
    LIMIT="$DEFAULT_LIMIT"
    FORCE_VERTICAL="0"
    AUTO="0"
    LIMIT_SET="0"

    shift 2
    for arg in "$@"; do
      if [ "$arg" = "auto" ]; then
        AUTO="1"
        continue
      fi
      if [ "$arg" = "v" ]; then
        FORCE_VERTICAL="1"
        continue
      fi
      if is_number "$arg"; then
        if [ "$LIMIT_SET" = "1" ]; then
          echo "Parâmetro inválido."
          usage
          exit 1
        fi
        LIMIT="$arg"
        LIMIT_SET="1"
        continue
      fi
      echo "Parâmetro inválido."
      usage
      exit 1
    done

    run_tail() {
      ORDER_COL="$(resolve_tail_order "$TABLE")"
      if [ -z "$ORDER_COL" ]; then
        echo "Aviso: tabela '$TABLE' sem id/created_at/updated_at; exibindo LIMIT simples."
        ORDER_SQL=""
      else
        ORDER_SQL="ORDER BY \`$ORDER_COL\` DESC"
      fi

      COLS="$(get_column_count "$TABLE")"
      if [ "$FORCE_VERTICAL" = "1" ] || [ "${COLS:-0}" -gt "$WIDE_COL_THRESHOLD" ]; then
        run_mysql "SELECT * FROM \`$TABLE\` $ORDER_SQL LIMIT $LIMIT\G"
      else
        run_mysql "SELECT * FROM \`$TABLE\` $ORDER_SQL LIMIT $LIMIT;"
      fi
    }

    if [ "$AUTO" = "1" ]; then
      while true; do
        clear_screen
        echo "[m] tail $TABLE (limit=$LIMIT) $(date '+%Y-%m-%d %H:%M:%S')"
        run_tail
        sleep 2
      done
    else
      run_tail
    fi
    ;;
  *)
    TABLE="$(resolve_table_arg "$1")"
    LIMIT="$DEFAULT_LIMIT"
    FORCE_VERTICAL="0"

    if [ "${2:-}" = "filter" ] || [ "${2:-}" = "f" ]; then
      shift 2
      [ "${1:-}" = "" ] && { echo "Informe a cláusula WHERE."; exit 1; }
      if [ "${!#}" = "v" ]; then
        FORCE_VERTICAL="1"
        set -- "${@:1:$(($#-1))}"
      fi
      WHERE_CLAUSE="$*"
      COLS="$(get_column_count "$TABLE")"

      if [ "$FORCE_VERTICAL" = "1" ] || [ "${COLS:-0}" -gt "$WIDE_COL_THRESHOLD" ]; then
        run_mysql "SELECT * FROM \`$TABLE\` WHERE $WHERE_CLAUSE LIMIT $LIMIT\G"
      else
        run_mysql "SELECT * FROM \`$TABLE\` WHERE $WHERE_CLAUSE LIMIT $LIMIT;"
      fi
      exit 0
    fi

    if [ "${2:-}" != "" ]; then
      if is_number "$2"; then
        LIMIT="$2"
        [ "${3:-}" = "v" ] && FORCE_VERTICAL="1"
      elif [ "$2" = "v" ]; then
        FORCE_VERTICAL="1"
      else
        echo "Parâmetro inválido."
        usage
        exit 1
      fi
    fi

    COLS="$(get_column_count "$TABLE")"

    if [ "$FORCE_VERTICAL" = "1" ] || [ "${COLS:-0}" -gt "$WIDE_COL_THRESHOLD" ]; then
      run_mysql "SELECT * FROM \`$TABLE\` LIMIT $LIMIT\G"
    else
      run_mysql "SELECT * FROM \`$TABLE\` LIMIT $LIMIT;"
    fi
    ;;
esac
