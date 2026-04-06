#!/bin/sh
# Helper: diagdb_parse.sh - Parses diagdb output for verification
# NOT an entry script — does not call init test, write_ok/write_nok, or finish.

. $init_path/init.sh

input_file=$1
output_file=$2

if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    echo "Usage: $0 <input_file> <output_file>"
    exit 1
fi

if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found"
    exit 1
fi

# Extract diagnostic information
echo "=== Parsed Diagdb Output ===" > "$output_file"
grep "Number of pages" "$input_file" | awk '{print $4}' >> "$output_file" 2>/dev/null
grep "Volume:" "$input_file" | head -5 >> "$output_file" 2>/dev/null

exit 0
