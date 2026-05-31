---
quick_id: 260531-wb7
status: complete
created: 2026-05-31
---

# Quick Task: Network Process Menu Top 5

Adjust the status item dropdown to show the five highest network-usage processes, one process per row, with process name plus upload/download rates on the same row.

## Plan

1. Change `ProcessNetworkReader` from returning one process to returning the top five active processes.
2. Replace the menu's separate download/upload/total/update rows with five reusable process rows.
3. Format each row as process identity plus upload and download rates.
4. Build and verify the installed app menu through Accessibility.
