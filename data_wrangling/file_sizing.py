import os

# Update this path to where your actual 1.4 GB file lives
input_file = r"Filepath of csv file"  
output_prefix = r"Filepath for folder output snowflake_part_"
# 20 MB in bytes (keeps you safely under Snowflake's web UI limit)
max_file_size_bytes = 240 * 1024 * 1024  

with open(input_file, "r", encoding="utf-8") as f:
    header = f.readline()  # Capture the first line (headers)
    header_bytes_len = len(header.encode("utf-8"))
    
    file_count = 1
    current_out_file = None
    current_file_size = 0

    for line in f:
        # If no file is open, create a new chunk and write the header first
        if current_out_file is None:
            output_name = f"{output_prefix}{file_count}.csv"
            current_out_file = open(output_name, "w", encoding="utf-8")
            current_out_file.write(header)
            current_file_size = header_bytes_len
            print(f"Creating: {output_name}")

        # Write data line
        current_out_file.write(line)
        current_file_size += len(line.encode("utf-8"))

        # Close the file if the next line risks crossing the 20MB threshold
        if current_file_size >= max_file_size_bytes:
            current_out_file.close()
            current_out_file = None
            file_count += 1

    # Clean up the last file
    if current_out_file is not None:
        current_out_file.close()

print("Splitting complete!")
