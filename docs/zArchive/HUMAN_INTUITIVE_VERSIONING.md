# 🧠 Human-Intuitive Versioning System

## Overview

Manifest CLI now uses a **human-intuitive versioning system** that matches how people naturally think about version numbers:

- **LEFT components = More MAJOR changes (bigger impact)**
- **RIGHT components = More MINOR changes (smaller impact)**
- **More digits after last dot = More specific/precise changes**

## 🎯 How It Works

### Standard Semantic Versioning (XX.XX.XX)

```
Version: 1.0.0
         │ │ │
         │ │ └── PATCH (rightmost = smallest impact)
         │ └──── MINOR (middle = moderate impact)
         └────── MAJOR (leftmost = biggest impact)
```

**Commands:**
- `manifest go major` → increments component 1 → **2.0.0**
- `manifest go minor` → increments component 2 → **1.1.0**
- `manifest go patch` → increments component 3 → **1.0.1**
- `manifest go revision` → increments component 4 → **1.0.0.1**

### Enterprise Versioning (XXXX.XXXX.XXXX)

```
Version: 0001.0001.0001
         │    │    │
         │    │    └── PATCH (rightmost = smallest impact)
         │    └───── MINOR (middle = moderate impact)
         └────────── MAJOR (leftmost = biggest impact)
```

**Commands:**
- `manifest go major` → increments component 1 → **0002.0000.0000**
- `manifest go minor` → increments component 2 → **0001.0002.0000**
- `manifest go patch` → increments component 3 → **0001.0001.0002**
- `manifest go revision` → increments component 4 → **0001.0001.0001.0001**

### Date-Based Versioning (YYYY.MM.DD)

```
Version: 2024.01.15
         │    │  │
         │    │  └── DAY (rightmost = smallest impact)
         │    └──── MONTH (middle = moderate impact)
         └─────── YEAR (leftmost = biggest impact)
```

**Commands:**
- `manifest go major` → increments component 1 → **2025.01.01**
- `manifest go minor` → increments component 2 → **2024.02.01**
- `manifest go patch` → increments component 3 → **2024.01.16**
- `manifest go revision` → increments component 4 → **2024.01.15.01**

### Build Number Versioning (X.X.X.X)

```
Version: 1.0.0.1
         │ │ │ │
         │ │ │ └── REVISION (most right = most specific)
         │ │ └──── PATCH (rightmost = least impact)
         │ └───── MINOR (middle = moderate impact)
         └─────── MAJOR (leftmost = biggest impact)
```

**Commands:**
- `manifest go major` → increments component 1 → **2.0.0.0**
- `manifest go minor` → increments component 2 → **1.1.0.0**
- `manifest go patch` → increments component 3 → **1.0.1.0**
- `manifest go revision` → increments component 4 → **1.0.0.2**

## 🔧 Configuration Variables

### Component Mapping
```bash
# Which component represents each type of change
MANIFEST_MAJOR_COMPONENT_POSITION="1"        # First position (leftmost)
MANIFEST_MINOR_COMPONENT_POSITION="2"        # Second position (middle)
MANIFEST_PATCH_COMPONENT_POSITION="3"        # Third position (rightmost)
MANIFEST_REVISION_COMPONENT_POSITION="4"     # Fourth position (most right)
```

### Increment Behavior
```bash
# Which component each command increments
MANIFEST_MAJOR_INCREMENT_TARGET="1"          # 'manifest go major' increments this
MANIFEST_MINOR_INCREMENT_TARGET="2"          # 'manifest go minor' increments this
MANIFEST_PATCH_INCREMENT_TARGET="3"          # 'manifest go patch' increments this
MANIFEST_REVISION_INCREMENT_TARGET="4"       # 'manifest go revision' increments this
```

### Reset Behavior
```bash
# Which components reset to 0 when incrementing others
MANIFEST_MAJOR_RESET_COMPONENTS="2,3,4"     # Reset minor/patch/revision when major changes
MANIFEST_MINOR_RESET_COMPONENTS="3,4"       # Reset patch/revision when minor changes
MANIFEST_PATCH_RESET_COMPONENTS="4"          # Reset revision when patch changes
MANIFEST_REVISION_RESET_COMPONENTS=""        # No reset for revision (additive)
```

## 🎨 Customization Examples

### Example 1: Reverse Logic (Right = Major, Left = Minor)
```bash
MANIFEST_VERSION_FORMAT="X.X.X"
MANIFEST_MAJOR_COMPONENT_POSITION="3"        # Rightmost = biggest impact
MANIFEST_MINOR_COMPONENT_POSITION="2"        # Middle = moderate impact
MANIFEST_PATCH_COMPONENT_POSITION="1"        # Leftmost = smallest impact

# Version: 1.0.0
# 'manifest go major' → 1.0.1 (increments rightmost)
# 'manifest go minor' → 1.1.0 (increments middle)
# 'manifest go patch' → 2.0.0 (increments leftmost)
```

### Example 2: Custom Separators
```bash
MANIFEST_VERSION_FORMAT="X-X-X"
MANIFEST_VERSION_SEPARATOR="-"

# Version: 1-0-0
# 'manifest go major' → 2-0-0
# 'manifest go minor' → 1-1-0
# 'manifest go patch' → 1-0-1
```

### Example 3: Mixed Format
```bash
MANIFEST_VERSION_FORMAT="vX.X.X"
MANIFEST_VERSION_SEPARATOR="."

# Version: v1.0.0
# 'manifest go major' → v2.0.0
# 'manifest go minor' → v1.1.0
# 'manifest go patch' → v1.0.1
```

## 💡 Benefits

1. **Intuitive**: Matches how humans naturally think about version numbers
2. **Flexible**: Supports any versioning scheme your organization uses
3. **Consistent**: Same commands work regardless of format
4. **Configurable**: Easy to customize for different needs
5. **Maintainable**: Clear separation of concerns

## 🚀 Getting Started

1. **Copy `env.example` to `.env`** in your project root
2. **Customize the versioning variables** for your organization
3. **Test with `manifest config`** to see your current settings
4. **Use `manifest go [type]`** to increment versions

## 🔍 View Current Configuration

```bash
manifest config
```

This shows all your current settings and explains how the system works with your configuration.
