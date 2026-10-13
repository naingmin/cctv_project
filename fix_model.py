with open('C:\\Users\\user\\Desktop\\Project\\lib\\data\\models\\cctv_record_model.dart', 'r') as f:
    lines = f.readlines()

# Filter out direction field and related references
new_lines = []
for line in lines:
    stripped = line.strip()
    
    # Skip the final String? direction; line
    if stripped == 'final String? direction;':
        continue
    
    # Skip this.direction references in constructor params
    if 'this.direction,' in line:
        continue
    
    # Skip direction: in constructor
    if 'direction:' in line and 'this.direction' in line:
        # Check if it's the direction assignment
        if 'direction ?? this.direction' in line or 'direction ??= this.direction' in line:
            continue
    
    new_lines.append(line)

with open('C:\\Users\\user\\Desktop\\Project\\lib\\data\\models\\cctv_record_model.dart', 'w') as f:
    f.writelines(new_lines)

print('SUCCESS: cctv_record_model.dart direction field removed')