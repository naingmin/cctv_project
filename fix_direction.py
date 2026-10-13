with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'r') as f:
    content = f.read()

# Remove the direction case from updateField
old = """      case 'direction':
        state = state.copyWith(direction: value);
        break;"""

new = ''

if old in content:
    content = content.replace(old, new)
    print('SUCCESS: Removed direction case from updateField')
else:
    print('Pattern not found')

with open('C:\\Users\\user\\Desktop\\Project\\lib\\features\\cctv\\providers\\cctv_form_provider.dart', 'w') as f:
    f.write(content)