#!/bin/bash

# ==========================================
# UPL Interpreter - Reborn Foundation
# Ukong Programming Language
# Author: Gemini
# ==========================================

# --- WARNA & STYLE ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- GLOBAL STATE ---
LINE_NUMBER=0
EXECUTION_HALTED=false

# ==============================================================================
# BAGIAN 1: TOKENIZER / LEXER
# ==============================================================================
# Deskripsi:
# Fungsi ini memecah satu baris kode menjadi token-token individual.
# Setiap token memiliki tipe (misal: IDENTIFIER, STRING, NUMBER) dan nilainya.
# Pendekatan ini lebih stabil daripada regex tunggal yang kompleks.
# Outputnya adalah string yang dipisahkan baris baru, format: "TYPE:VALUE"

tokenize() {
    local line="$1"
    local tokens=()
    local current_pos=0
    local line_len=${#line}

    while [[ $current_pos -lt $line_len ]]; do
        local char="${line:$current_pos:1}"

        # 1. Skip whitespace
        if [[ "$char" =~ [[:space:]] ]]; then
            ((current_pos++))
            continue
        fi

        # 2. String literals (kutip ganda)
        if [[ "$char" == "\"" ]]; then
            local value=""
            ((current_pos++)) # Lewati kutip pembuka
            while [[ $current_pos -lt $line_len ]]; do
                local str_char="${line:$current_pos:1}"
                if [[ "$str_char" == "\"" ]]; then
                    break
                fi
                value+="$str_char"
                ((current_pos++))
            done
            tokens+=("STRING:$value")
            ((current_pos++)) # Lewati kutip penutup
            continue
        fi

        # 3. Numbers (integer & float dasar)
        if [[ "$char" =~ [0-9] ]]; then
            local value="$char"
            ((current_pos++))
            while [[ $current_pos -lt $line_len ]]; do
                local next_char="${line:$current_pos:1}"
                if [[ "$next_char" =~ [0-9] || ( "$next_char" == "." && ! "$value" == *"."* ) ]]; then
                    value+="$next_char"
                    ((current_pos++))
                else
                    break
                fi
            done
            tokens+=("NUMBER:$value")
            continue
        fi

        # 4. Identifiers (variables, function names, keywords)
        if [[ "$char" =~ [a-zA-Z_] ]]; then
            local value="$char"
            ((current_pos++))
            while [[ $current_pos -lt $line_len ]]; do
                local next_char="${line:$current_pos:1}"
                if [[ "$next_char" =~ [a-zA-Z0-9_] ]]; then
                    value+="$next_char"
                    ((current_pos++))
                else
                    break
                fi
            done
            # Keyword check
            case "$value" in
                "jika"|"selama"|"ulangi"|"fungsi"|"selesai"|"lainnya"|"kembali"|"cetak")
                    tokens+=("KEYWORD:$value")
                    ;;
                "benar"|"salah")
                    tokens+=("BOOLEAN:$value")
                    ;;
                *)
                    tokens+=("IDENTIFIER:$value")
                    ;;
            esac
            continue
        fi

        # 5. Operators & Punctuation
        local op_char="${line:$current_pos:2}"
        if [[ "$op_char" == "==" || "$op_char" == "!=" || "$op_char" == ">=" || "$op_char" == "<=" ]]; then
            tokens+=("OPERATOR:$op_char")
            current_pos=$((current_pos + 2))
            continue
        fi

        op_char="$char"
        case "$op_char" in
            "+"|"-"|"*"|"/"|"%"|"="|"."|">"|"<")
                tokens+=("OPERATOR:$op_char")
                ;;
            "("|")"|","|"["|"]"|":")
                # Menggunakan nama unik untuk membedakan
                case "$op_char" in
                    "(") tokens+=("LPAREN:(") ;; 
                    ")") tokens+=("RPAREN:)") ;; 
                    "[") tokens+=("LBRACKET:[") ;; 
                    "]") tokens+=("RBRACKET:]") ;; 
                    ",") tokens+=("COMMA:,") ;; 
                    ":") tokens+=("COLON::") ;; 
                esac
                ;; 
            "#") # Komentar, abaikan sisa baris
                current_pos=$line_len
                ;; 
            *)
                tokens+=("UNKNOWN:$op_char")
                ;; 
        esac
        ((current_pos++))
    done

    # Cetak token, satu per baris
    for token in "${tokens[@]}"; do
        echo "$token"
    done
}

# --- Contoh Penggunaan Tokenizer ---
# echo "--- Uji Coba Tokenizer ---"
# KODE_UJI='nama_variabel = "Hello World" + 123.45 # komentar'
# tokenize "$KODE_UJI"
# echo "-------------------------"
# KODE_UJI_2='jika x >= 5: cetak(nama[0])'
# tokenize "$KODE_UJI_2"
# echo "-------------------------"

# ==============================================================================
# BAGIAN 4: SISTEM PENANGANAN ERROR
# ==============================================================================
# Deskripsi:
# Fungsi terpusat untuk melaporkan error. Menghentikan eksekusi dengan flag
# agar interpreter bisa berhenti dengan aman.
# Format: Error(type, message, line_number)

throw_error() {
    local type="$1"
    local message="$2"
    local line=${3:-$LINE_NUMBER}

    echo -e "${RED}${BOLD}[UPL Error]${NC} ($type) di baris $line: $message" >&2
    EXECUTION_HALTED=true
}


# ==============================================================================
# BAGIAN 3: STRUKTUR DATA INTERNAL
# ==============================================================================
# Deskripsi:
# Menggunakan Bash Associative Arrays untuk merepresentasikan data UPL.
# - Variabel: Disimpan berdasarkan tipe dan nilai.
# - Array: Disimpan sebagai key-value (NAMA_INDEX) dengan metadata panjang.
# - Fungsi: Menyimpan parameter dan isi (body) fungsi.

declare -A VAR_VALUES
declare -A VAR_TYPES

declare -A ARRAY_VALUES
declare -A ARRAY_LENGTH

declare -A FUNC_PARAMS
declare -A FUNC_BODY


# ==============================================================================
# BAGIAN 2: EVALUATOR
# ==============================================================================
# Deskripsi:
# Bagian ini bertanggung jawab untuk mengevaluasi token dan menjalankan logika.
# Untuk saat ini, parser matematika hanya mendukung integer untuk menghindari `bc`.
# `LATEST_EVAL_RESULT` digunakan untuk menyimpan hasil evaluasi terakhir.
# `LATEST_EVAL_TYPE` menyimpan tipe data dari hasil (number, string, boolean).

LATEST_EVAL_RESULT=""
LATEST_EVAL_TYPE=""

# Fungsi bantu untuk mendapatkan nilai dari sebuah token literal atau variabel
get_value_from_token() {
    local token="$1"
    local type="${token%%:*}"
    local value="${token#*:}"

    case "$type" in
        "NUMBER"|"STRING")
            LATEST_EVAL_RESULT="$value"
            LATEST_EVAL_TYPE="${type,,}" # lowercase type
            ;;
        "BOOLEAN")
            [[ "$value" == "benar" ]] && LATEST_EVAL_RESULT=1 || LATEST_EVAL_RESULT=0
            LATEST_EVAL_TYPE="boolean"
            ;;
        "IDENTIFIER")
            if [[ -v VAR_VALUES[$value] ]]; then
                LATEST_EVAL_RESULT="${VAR_VALUES[$value]}"
                LATEST_EVAL_TYPE="${VAR_TYPES[$value]}"
            else
                throw_error "NameError" "Variabel '$value' tidak ditemukan."
                return 1
            fi
            ;;
        *)
            throw_error "SyntaxError" "Token tidak terduga '$value' saat mencari nilai."
            return 1
            ;;
    esac
    return 0
}


# Evaluator ekspresi yang lebih cerdas
# Fungsi ini menentukan apakah akan melakukan konkatenasi string atau evaluasi matematika.
evaluate_expression() {
    local tokens=("$@")
    local is_string_expr=false

    # Deteksi tipe ekspresi: jika ada string literal atau variabel string,
    # maka ini adalah konkatenasi string.
    for token in "${tokens[@]}"; do
        local type="${token%%:*}"
        local value="${token#*:}"
        if [[ "$type" == "STRING" ]]; then
            is_string_expr=true
            break
        fi
        if [[ "$type" == "IDENTIFIER" && "${VAR_TYPES[$value]}" == "string" ]]; then
            is_string_expr=true
            break
        fi
    done

    # Jika hanya ada satu token, cukup dapatkan nilainya
    if [[ ${#tokens[@]} -eq 1 ]]; then
        get_value_from_token "${tokens[0]}"
        return $?
    fi

    # Proses berdasarkan tipe ekspresi
    if $is_string_expr; then
        # Lakukan konkatenasi string
        local final_string=""
        for token in "${tokens[@]}"; do
            local type="${token%%:*}"
            local value="${token#*:}"
            if [[ "$type" == "OPERATOR" && "$value" == "+" ]]; then
                continue # Abaikan operator + dalam mode string
            fi
            
            # Untuk token selain operator, dapatkan nilainya dan gabungkan
            if [[ "$type" != "OPERATOR" ]]; then
                get_value_from_token "$token"
                if $EXECUTION_HALTED; then return 1; fi
                final_string+="$LATEST_EVAL_RESULT"
            fi
        done
        LATEST_EVAL_RESULT="$final_string"
        LATEST_EVAL_TYPE="string"
    else
        # Lakukan evaluasi matematika (integer)
        local expression=""
        for token in "${tokens[@]}"; do
            local type="${token%%:*}"
            local value="${token#*:}"

            if [[ "$type" == "IDENTIFIER" ]]; then
                if [[ -v VAR_VALUES[$value] && ("${VAR_TYPES[$value]}" == "number" || "${VAR_TYPES[$value]}" == "boolean") ]]; then
                    expression+="${VAR_VALUES[$value]}"
                else
                    throw_error "TypeError" "Variabel '$value' bukan angka untuk operasi matematika."
                    return 1
                fi
            elif [[ "$type" == "NUMBER" ]]; then
                expression+="${value%%.*}" # Hilangkan desimal untuk aritmatika integer
            elif [[ "$type" == "OPERATOR" || "$type" == "LPAREN" || "$type" == "RPAREN" ]]; then
                expression+="$value"
            fi
        done

        if [[ -z "$expression" ]]; then
            # Ini bisa terjadi jika ekspresi hanya berisi token yang diabaikan.
            # Kembalikan nilai default atau error. Kita anggap ini sebagai error.
            throw_error "ValueError" "Ekspresi matematika kosong atau tidak valid."
            return 1
        fi

        local result
        if result=$(eval echo $((expression)) 2>/dev/null); then
            LATEST_EVAL_RESULT="$result"
            LATEST_EVAL_TYPE="number"
        else
            throw_error "MathError" "Ekspresi matematika tidak valid: '$expression'."
            return 1
        fi
    fi
    return 0
}


# --- Contoh Penggunaan Evaluator ---
# echo "--- Uji Coba Evaluator ---"
# VAR_VALUES["x"]=10
# VAR_TYPES["x"]="number"
# VAR_VALUES["y"]=20
# VAR_TYPES["y"]="number"
# TOKENS_TO_EVAL=("IDENTIFIER:x" "OPERATOR:+" "IDENTIFIER:y" "OPERATOR:*" "NUMBER:2")
# evaluate_expression "${TOKENS_TO_EVAL[@]}"
# if ! $EXECUTION_HALTED; then
#     echo "Hasil evaluasi: $LATEST_EVAL_RESULT (Tipe: $LATEST_EVAL_TYPE)"
# fi
# echo "-------------------------"

# Variabel global untuk eksekusi mode file
declare -a CODE_LINES
EXECUTION_POINTER=0
declare -a IF_STACK

# Helper untuk menemukan penanda blok 'lainnya' dan 'selesai'
# Argumen 1: Posisi baris 'jika'
# Output: Menyimpan hasil di array global BLOCK_MARKERS
declare -A BLOCK_MARKERS
find_block_markers() {
    local start_line=$1
    BLOCK_MARKERS=([else]=-1 [end]=-1)

    local level=1
    for (( i=$((start_line + 1)); i<${#CODE_LINES[@]}; i++ )); do
        local line_content="${CODE_LINES[$i]}"
        local clean_line="${line_content%%#*}"
        clean_line="$(echo "$clean_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        local first_word; first_word=$(echo "$clean_line" | awk '{print $1}')
        first_word=${first_word//:}

        if [[ "$first_word" == "jika" || "$first_word" == "selama" ]]; then
            ((level++))
        elif [[ "$first_word" == "selesai" ]]; then
            ((level--))
            if [[ $level -eq 0 ]]; then
                BLOCK_MARKERS[end]=$i
                # Jangan langsung return, kita mungkin masih perlu 'else'
                if [[ ${BLOCK_MARKERS[else]} -ne -1 ]]; then return; fi
            fi
        elif [[ "$first_word" == "lainnya" && $level -eq 1 ]]; then
            BLOCK_MARKERS[else]=$i
            if [[ ${BLOCK_MARKERS[end]} -ne -1 ]]; then return; fi
        fi
    done
}

# Helper untuk menemukan 'selesai' yang cocok untuk blok apapun
# Argumen 1: Posisi baris awal blok
# Output: Menyimpan hasil di variabel global END_MARKER
END_MARKER=-1
find_end_of_block() {
    local start_line=$1
    END_MARKER=-1
    local level=1
    for (( i=$((start_line + 1)); i<${#CODE_LINES[@]}; i++ )); do
        local line_content="${CODE_LINES[$i]}"
        local clean_line="${line_content%%#*}"
        clean_line="$(echo "$clean_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        local first_word; first_word=$(echo "$clean_line" | awk '{print $1}')
        first_word=${first_word//:}
        if [[ "$first_word" == "jika" || "$first_word" == "selama" ]]; then
            ((level++))
        elif [[ "$first_word" == "selesai" ]]; then
            ((level--))
            if [[ $level -eq 0 ]]; then
                END_MARKER=$i
                return
            fi
        fi
    done
}

# Fungsi ini mem-parsing dan mengeksekusi stream kode
execute_code_stream() {
    while [[ $EXECUTION_POINTER -lt ${#CODE_LINES[@]} ]]; do
        local current_line_index=$EXECUTION_POINTER
        local line="${CODE_LINES[$current_line_index]}"
        LINE_NUMBER=$((current_line_index + 1))

        ((EXECUTION_POINTER++)) # Selalu maju, kecuali ada lompatan

        local clean_line="${line%%#*}"
        clean_line="$(echo "$clean_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -z "$clean_line" ]]; then continue; fi

        local -a tokens; IFS=$'\n' read -d '' -ra tokens < <(tokenize "$clean_line")
        if $EXECUTION_HALTED; then return 1; fi
        if [[ ${#tokens[@]} -eq 0 ]]; then continue; fi

        local first_token_type="${tokens[0]%%:*}"
        local first_token_value="${tokens[0]#*:}"

        if [[ "$first_token_type" == "KEYWORD" ]]; then
            case "$first_token_value" in
                "jika")
                    find_block_markers $current_line_index
                    if [[ ${BLOCK_MARKERS[end]} -eq -1 ]]; then
                        throw_error "SyntaxError" "Blok 'jika' di baris $LINE_NUMBER tidak pernah ditutup."
                        return 1
                    fi

                    local -a cond_tokens=(); local colon_found=false
                    for (( i=1; i<${#tokens[@]}; i++ )); do
                        if [[ "${tokens[$i]}" == "COLON::" ]]; then colon_found=true; break; fi
                        cond_tokens+=("${tokens[$i]}")
                    done
                    if ! $colon_found || [[ ${#cond_tokens[@]} -eq 0 ]]; then
                        throw_error "SyntaxError" "Sintaks 'jika <kondisi>:' tidak valid di baris $LINE_NUMBER."
                        return 1
                    fi

                    evaluate_expression "${cond_tokens[@]}"
                    if $EXECUTION_HALTED; then return 1; fi
                    
                    if [[ "$LATEST_EVAL_RESULT" == "0" || "$LATEST_EVAL_RESULT" == "salah" ]]; then
                        # KONDISI SALAH -> Lompat ke 'lainnya' atau 'selesai'
                        if [[ ${BLOCK_MARKERS[else]} -ne -1 ]]; then
                            EXECUTION_POINTER=$(( ${BLOCK_MARKERS[else]} ))
                        else
                            EXECUTION_POINTER=$(( ${BLOCK_MARKERS[end]} ))
                        fi
                    fi
                    ;;
                "selama")
                    find_end_of_block $current_line_index
                    if [[ $END_MARKER -eq -1 ]]; then
                        throw_error "SyntaxError" "Blok 'selama' di baris $LINE_NUMBER tidak pernah ditutup."
                        return 1
                    fi

                    local -a cond_tokens=(); local colon_found=false
                    for (( i=1; i<${#tokens[@]}; i++ )); do
                        if [[ "${tokens[$i]}" == "COLON::" ]]; then colon_found=true; break; fi
                        cond_tokens+=("${tokens[$i]}")
                    done
                    if ! $colon_found || [[ ${#cond_tokens[@]} -eq 0 ]]; then
                        throw_error "SyntaxError" "Sintaks 'selama <kondisi>:' tidak valid di baris $LINE_NUMBER."
                        return 1
                    fi

                    evaluate_expression "${cond_tokens[@]}"
                    if $EXECUTION_HALTED; then return 1; fi
                    
                    if [[ "$LATEST_EVAL_RESULT" == "0" || "$LATEST_EVAL_RESULT" == "salah" ]]; then
                        # KONDISI SALAH -> Lompat ke SETELAH 'selesai'
                        EXECUTION_POINTER=$(( END_MARKER + 1 ))
                    fi
                    ;;
                "lainnya")
                    # Jika kita sampai di 'lainnya' secara alami, itu berarti blok 'jika'
                    # sebelumnya dieksekusi (kondisi benar). Jadi, kita harus melompat
                    # ke akhir blok 'jika-lainnya' ini.
                    find_end_of_block $current_line_index
                     if [[ $END_MARKER -ne -1 ]]; then
                        EXECUTION_POINTER=$(( END_MARKER + 1 ))
                    else
                         throw_error "SyntaxError" "Tidak dapat menemukan 'selesai' yang cocok untuk 'lainnya' di baris $LINE_NUMBER."
                         return 1
                    fi
                    ;;
                "selesai")
                    # Cari tahu blok apa yang ditutup oleh 'selesai' ini
                    local opener_line=-1
                    local opener_type=""
                    local level=1
                    for (( i=$((current_line_index - 1)); i>=0; i-- )); do
                        local clean_prev_line="$(echo "${CODE_LINES[$i]}" | sed -e 's/^[[:space:]]*//' | awk '{print $1}')"
                        clean_prev_line=${clean_prev_line//:}
                        if [[ "$clean_prev_line" == "selesai" ]]; then
                            ((level++))
                        elif [[ "$clean_prev_line" == "jika" || "$clean_prev_line" == "selama" ]]; then
                            ((level--))
                            if [[ $level -eq 0 ]]; then
                                opener_line=$i
                                opener_type=$clean_prev_line
                                break
                            fi
                        fi
                    done

                    if [[ "$opener_type" == "selama" ]]; then
                        EXECUTION_POINTER=$opener_line
                    fi
                    ;;
                "cetak")
                    if [[ "${tokens[1]}" != "LPAREN:(" ]]; then throw_error "SyntaxError" "Membutuhkan '(' setelah 'cetak'."; return 1; fi
                    local -a inner_tokens=("${tokens[@]:2}")

                    if [[ ${#inner_tokens[@]} -eq 0 || "${inner_tokens[-1]}" != "RPAREN:)" ]]; then
                        throw_error "SyntaxError" "Sintaks 'cetak()' tidak valid atau kurung tutup hilang."
                        return 1
                    fi
                    unset 'inner_tokens[${#inner_tokens[@]}-1]' # Hapus RPAREN

                    if [[ ${#inner_tokens[@]} -eq 0 ]]; then
                        echo # Perintah cetak() tanpa argumen menghasilkan baris baru
                        continue
                    fi

                    local output_parts=(); local current_arg_tokens=()
                    inner_tokens+=("COMMA:,")
                    for pt in "${inner_tokens[@]}"; do
                        if [[ "$pt" == "COMMA:," ]]; then
                            if [[ ${#current_arg_tokens[@]} -gt 0 ]]; then
                                evaluate_expression "${current_arg_tokens[@]}"; if $EXECUTION_HALTED; then return 1; fi
                                output_parts+=("$LATEST_EVAL_RESULT")
                                current_arg_tokens=()
                            elif [[ "$pt" != "${inner_tokens[-1]}" ]]; then throw_error "SyntaxError" "Ekspresi kosong di antara koma."; return 1; fi
                        else current_arg_tokens+=("$pt"); fi
                    done
                    echo "${output_parts[@]}"
                    ;;
                *)
                    throw_error "SyntaxError" "Keyword '$first_token_value' tidak bisa memulai statement."
                    return 1
                    ;;
            esac
        elif [[ ("$first_token_type" == "IDENTIFIER" || "$first_token_type" == "BOOLEAN") && "${tokens[1]}" == "OPERATOR:=" ]]; then
            local var_name="$first_token_value"; local -a expr_tokens=("${tokens[@]:2}")
            if [[ ${#expr_tokens[@]} -eq 0 ]]; then throw_error "SyntaxError" "Ekspresi kosong setelah '='."; return 1; fi
            evaluate_expression "${expr_tokens[@]}"; if $EXECUTION_HALTED; then return 1; fi
            VAR_VALUES["$var_name"]="$LATEST_EVAL_RESULT"
            VAR_TYPES["$var_name"]="$LATEST_EVAL_TYPE"
        else
            throw_error "SyntaxError" "Perintah tidak dikenal: '$clean_line'"
            return 1
        fi
    done
}

# Parser sederhana khusus untuk REPL
parse_and_execute_repl_line() {
    local line="$1"; LINE_NUMBER=1
    local clean_line="${line%%#*}"; clean_line="$(echo "$clean_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "$clean_line" ]]; then return 0; fi
    local -a tokens; IFS=$'\n' read -d '' -ra tokens < <(tokenize "$clean_line")
    if $EXECUTION_HALTED || [[ ${#tokens[@]} -eq 0 ]]; then return 1; fi
    local f_type="${tokens[0]%%:*}"; local f_val="${tokens[0]#*:}"
    if [[ "$f_type" == "KEYWORD" && ("$f_val" == "jika" || "$f_val" == "selama" || "$f_val" == "ulangi") ]]; then
        throw_error "REPLError" "Struktur blok '$f_val' tidak didukung di REPL."; return 1
    fi
    if ! ( [[ "$f_type" == "IDENTIFIER" && "${tokens[1]}" == "OPERATOR:=" ]] || [[ "$f_val" == "cetak" ]] ); then
        evaluate_expression "${tokens[@]}"; if ! $EXECUTION_HALTED; then echo "$LATEST_EVAL_RESULT"; fi
    else
        local old_lines=("${CODE_LINES[@]}"); local old_pointer=$EXECUTION_POINTER
        CODE_LINES=("$line"); EXECUTION_POINTER=0
        execute_code_stream
        CODE_LINES=("${old_lines[@]}"); EXECUTION_POINTER=$old_pointer
    fi
}

# ==============================================================================
# MAIN INTERPRETER LOOP
# ==============================================================================

SCRIPT_FILE="$1" 

main() {
    if [[ -z "$SCRIPT_FILE" ]]; then
        # REPL Mode
        echo -e "${GREEN}UPL v0.4 (Final Control Flow) - REPL Mode${NC}"
        echo -e "${YELLOW}Ketik 'keluar' untuk keluar.${NC}"
        while true; do
            read -e -p "$(echo -e "${BOLD}upl>${NC} ")" input
            if [[ "$input" == "keluar" ]]; then echo -e "${YELLOW}Keluar dari UPL REPL.${NC}"; break; fi
            parse_and_execute_repl_line "$input"
            if $EXECUTION_HALTED; then EXECUTION_HALTED=false; fi
        done
    else
        # File Mode
        if [[ ! -f "$SCRIPT_FILE" ]]; then echo -e "${RED}Error: File '$SCRIPT_FILE' tidak ditemukan.${NC}"; exit 1; fi
        mapfile -t CODE_LINES < "$SCRIPT_FILE"
        EXECUTION_POINTER=0
        execute_code_stream
        if $EXECUTION_HALTED; then exit 1; fi
    fi
}

# Jalankan main loop
main

# ==============================================================================
# BAGIAN 5: GRAMMAR DASAR UPL (MINIMAL)
# ==============================================================================
# Deskripsi:
# Grammar ini mendefinisikan struktur dasar sintaks UPL.
# Ditulis dalam format pseudo-BNF untuk kejelasan.
#
# <program> ::= <statement>*
#
# <statement> ::= <assignment_statement>
#               | <function_call>
#               | <if_statement>
#               | <loop_statement>
#               | <print_statement>
#               | <return_statement>
#
# <assignment_statement> ::= IDENTIFIER "=" <expression>
#                          | IDENTIFIER "[" <expression> "]" "=" <expression>
#
# <print_statement> ::= "cetak" "(" <expression> ("," <expression>)* ")"
#
# <expression> ::= <term> (("+"|"-") <term>)*   // Penjumlahan, Pengurangan
#                | <string_concatenation>
#
# <term> ::= <factor> (("*"|"/"|"%") <factor>)* // Perkalian, Pembagian
#
# <factor> ::= NUMBER
#            | STRING
#            | BOOLEAN
#            | IDENTIFIER
#            | IDENTIFIER "[" <expression> "]"  // Akses array
#            | "(" <expression> ")"
#            | <function_call>
#
# <string_concatenation> ::= <expression> "+" <expression> // Minimal salah satunya harus string
#
# <function_call> ::= IDENTIFIER "(" <argument_list> ")"
#
# <argument_list> ::= <expression> ("," <expression>)* | ""
#
# <if_statement> ::= "jika" <expression> ":" <block> ("lainnya" ":" <block>)? "selesai"
#
# <loop_statement> ::= "ulangi" <expression> "kali" ":" <block> "selesai"
#                    | "selama" <expression> ":" <block> "selesai"
#
# <function_definition> ::= "fungsi" IDENTIFIER "(" <param_list> ")" ":" <block> "selesai"
#
# <param_list> ::= IDENTIFIER ("," IDENTIFIER)* | ""
#
# <return_statement> ::= "kembali" <expression>
#
# <block> ::= <statement>*
#
# ==============================================================================
# --- AKHIR DARI FONDASI DASAR ---
# ==============================================================================
# Interpreter loop utama dan pemrosesan baris per baris akan dibangun di atas fondasi ini.


# ==============================================================================
# BAGIAN 5: GRAMMAR DASAR UPL (MINIMAL)
# ==============================================================================
# Deskripsi:
# Grammar ini mendefinisikan struktur dasar sintaks UPL.
# Ditulis dalam format pseudo-BNF untuk kejelasan.
#
# <program> ::= <statement>*
#
# <statement> ::= <assignment_statement>
#               | <function_call>
#               | <if_statement>
#               | <loop_statement>
#               | <print_statement>
#               | <return_statement>
#
# <assignment_statement> ::= IDENTIFIER "=" <expression>
#                          | IDENTIFIER "[" <expression> "]" "=" <expression>
#
# <print_statement> ::= "cetak" "(" <expression> ("," <expression>)* ")"
#
# <expression> ::= <term> (("+"|"-") <term>)*   // Penjumlahan, Pengurangan
#                | <string_concatenation>
#
# <term> ::= <factor> (("*"|"/"|"%") <factor>)* // Perkalian, Pembagian
#
# <factor> ::= NUMBER
#            | STRING
#            | BOOLEAN
#            | IDENTIFIER
#            | IDENTIFIER "[" <expression> "]"  // Akses array
#            | "(" <expression> ")"
#            | <function_call>
#
# <string_concatenation> ::= <expression> "+" <expression> // Minimal salah satunya harus string
#
# <function_call> ::= IDENTIFIER "(" <argument_list> ")"
#
# <argument_list> ::= <expression> ("," <expression>)* | ""
#
# <if_statement> ::= "jika" <expression> ":" <block> ("lainnya" ":" <block>)? "selesai"
#
# <loop_statement> ::= "ulangi" <expression> "kali" ":" <block> "selesai"
#                    | "selama" <expression> ":" <block> "selesai"
#
# <function_definition> ::= "fungsi" IDENTIFIER "(" <param_list> ")" ":" <block> "selesai"
#
# <param_list> ::= IDENTIFIER ("," IDENTIFIER)* | ""
#
# <return_statement> ::= "kembali" <expression>
#
# <block> ::= <statement>*
#
# ==============================================================================
# --- AKHIR DARI FONDASI DASAR ---
# ==============================================================================
# Interpreter loop utama dan pemrosesan baris per baris akan dibangun di atas fondasi ini.



