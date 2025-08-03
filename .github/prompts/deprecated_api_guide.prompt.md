---
mode: agent
---
# Deprecated API Usage Guide

## Notice
To avoid errors, do not use deprecated APIs. If an API is marked as deprecated, search online and use the suggested replacement.

# Collaboration Notice
To facilitate collaboration, the prompt file must be written in English.

# Color Class Deprecation Notice
For the Color class, the following properties are deprecated:
- `red`, `green`, `blue`, `alpha` (type: int, range: 0-255)
Use instead:
- `r`, `g`, `b`, `a` (type: double, range: 0-1)

When migrating, ensure to convert values from int (0-255) to double (0-1) by dividing by 255.0.
Example:
```dart
// Deprecated
int red = color.red;

// Recommended
double r = color.r; // If migrating: double r = color.red / 255.0;
```

# Opacity Deprecation Notice
The following APIs are also deprecated:
- `opacity` (type: double, range: 0-1)
- `withOpacity(double opacity)`

Use instead:
- `a` (type: double, range: 0-1) for alpha channel
- `withValues(alpha: ...)` to create a new color with the specified alpha

Migration examples:
```dart
// Deprecated
double alpha = color.opacity;
final faded = color.withOpacity(0.5);

// Recommended
double alpha = color.a;
final faded = color.withValues(alpha: 0.5);
```

