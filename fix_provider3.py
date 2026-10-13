# Fix cctv_form_provider.dart - Remove direction from updateField
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'r') as f:
    content = f.read()

# Remove direction case from updateField method
content = content.replace('case \"direction\":\n        state = state.copyWith(direction: value);\n        break;', '')

# Write back
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'w') as f:
    f.write(content)

print('SUCCESS: Removed direction from updateField')