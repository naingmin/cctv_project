# Fix cctv_form_provider.dart - Remove direction from updateField
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'r') as f:
    lines = f.readlines()

# Remove direction case from updateField method (lines 220-222, 0-indexed 219-221)
new_lines = []
i = 0
while i < len(lines):
    # Check if this is the direction case
    if i < len(lines) - 2 and 'case \"direction\":' in lines[i] and 'state = state.copyWith(direction: value)' in lines[i+1] and 'break;' in lines[i+2]:
        # Skip these 3 lines
        i += 3
        continue
    new_lines.append(lines[i])
    i += 1

with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'w') as f:
    f.writelines(new_lines)

print('SUCCESS: Removed direction from updateField')