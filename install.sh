#!/bin/bash

# Skrip Instalasi untuk UPL (Ukong Programming Language)

# --- Konfigurasi ---
INSTALL_DIR="/data/data/com.termux/files/usr/bin"
SOURCE_FILE="upl_reborn.sh"
TARGET_NAME="upl"

# --- Warna ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Memulai instalasi UPL..."

# 1. Periksa apakah file sumber ada
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}Error: File sumber '$SOURCE_FILE' tidak ditemukan.${NC}"
    exit 1
fi

# 2. Pastikan direktori instalasi ada
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Direktori instalasi '$INSTALL_DIR' tidak ditemukan. Mungkin ini bukan lingkungan Termux."
    echo "Silakan edit skrip ini dan sesuaikan variabel INSTALL_DIR."
    exit 1
fi

# 3. Jadikan skrip interpreter dapat dieksekusi
echo "Memberikan izin eksekusi ke '$SOURCE_FILE'..."
chmod +x "$SOURCE_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}Gagal memberikan izin eksekusi.${NC}"
    exit 1
fi

# 4. Hapus file lama jika ada
echo "Menghapus instalasi '$TARGET_NAME' yang lama (jika ada)..."
rm -f "$INSTALL_DIR/$TARGET_NAME"

# 5. Salin file ke direktori instalasi
echo "Menyalin '$SOURCE_FILE' ke '$INSTALL_DIR/$TARGET_NAME'..."
cp "$SOURCE_FILE" "$INSTALL_DIR/$TARGET_NAME"
if [ $? -ne 0 ]; then
    echo -e "${RED}Gagal menyalin file. Coba jalankan dengan sudo jika perlu.${NC}"
    exit 1
fi

echo -e "${GREEN}Instalasi UPL berhasil!${NC}"
echo "Sekarang Anda dapat menjalankan interpreter dengan mengetik '$TARGET_NAME' dari mana saja."
echo "Contoh: $TARGET_NAME test.upl"
