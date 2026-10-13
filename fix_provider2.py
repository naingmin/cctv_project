# Fix cctv_form_provider.dart - Remove direction references
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'r') as f:
    content = f.read()

# 1. Remove direction from the class fields
content = content.replace('  final String? direction;\n', '  ')
content = content.replace('    this.direction,\n', '    ')

# 2. Remove direction from constructor
content = content.replace('''    this.region,
    this.township,
    this.street,
    this.direction,
    this.status = 'ACTIVE',''', '''    this.region,
    this.township,
    this.street,
    this.status = 'ACTIVE',''')

# 3. Remove direction from copyWith method parameters and body
content = content.replace('String? direction,\n    String? status,', 'String? status,')
content = content.replace('direction: direction ?? this.direction,', '')

# 4. Remove direction case from updateField method
content = content.replace('case \"direction\":\n        state = state.copyWith(direction: value);\n        break;', '')

# 5. Remove direction from submit method's CctvRecord creation
content = content.replace('direction: state.direction,', '')

# Write back
with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'w') as f:
    f.write(content)

print('SUCCESS: cctv_form_provider.dart direction references removed')