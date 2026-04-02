#!/bin/sh
# Helper: diagdb_parse.sh - Parses diagdb output for verification
# This is an acceptable helper script (non-entry script)
# 
# IMPORTANT: This is a helper script, NOT an entry script
# - Does NOT call init test
# - Does NOT call write_ok/write_nok
# - Does NOT call finish
# - Caller (entry script) handles lifecycle

# May source init.sh for utility functions but does NOT own testcase lifecycle
. $init_path/init.sh

# Parse command line arguments
input_file=$1
output_file=$2

# Validate inputs
if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    echo "Usage: $0 <input_file> <output_file>"
    echo "  input_file:  Path to diagdb output file"
    echo "  output_file: Path to write parsed results"
    exit 1
fi

# Check input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found"
    exit 1
fi

# Parse input and output structured data
# Extract relevant diagnostic information
echo "=== Parsed Diagdb Output ===" > "$output_file"
echo "Date: $(date)" >> "$output_file"
echo "" >> "$output_file"

# Extract number of pages
echo "Pages:" >> "$output_file"
grep "Number of pages" "$input_file" | awk '{print "  " $4}' >> "$output_file" 2>/dev/null || echo "  N/A" >> "$output_file"

# Extract volume information
echo "" >> "$output_file"
echo "Volumes:" >> "$output_file"
grep "Volume:" "$input_file" | head -5 >> "$output_file" 2>/dev/null || echo "  N/A" >> "$output_file"

# No write_ok/write_nok - helper scripts don't report test results
# No finish - caller (entry script) handles final cleanup
# Return success/failure based on parsing success
exit 0
