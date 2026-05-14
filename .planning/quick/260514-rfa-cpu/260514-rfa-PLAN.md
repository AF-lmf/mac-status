# Quick Task 260514-rfa: 继续修复 CPU 状态不显示

## Scope

CPU sampling succeeds, but the CPU status item is still not visible in the menu bar after the previous layout fix.

## Tasks

1. Make status item text assignment robust for variable-width AppKit sizing by setting both `title` and `attributedTitle`.
2. Explicitly mark status items visible after creation.
3. Build and restart the app so the user can verify the menu bar result.

