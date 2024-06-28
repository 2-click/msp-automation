### Unauthorized TeamViewer Connection Detection Script

This PowerShell script detects unauthorized TeamViewer connections by verifying if the connection's display name includes your organization's identifier. It is essential that the display name of your TeamViewer users contains a recognizable part of your company name.
It's made for NinjaOne but can be customized to your liking.

#### How It Works:
- The script reads the name of the client that connected via TeamViewer.
- It matches the display name against your organization's identifier.

#### Requirements:
- Ensure all user display names in TeamViewer include a part of your company name.
  
  Example:
  - **Valid:** Joe Doe - Pro IT Services
  - **Invalid:** Joe Doe (The script cannot determine if Joe Doe is part of your organization)

#### Security Note:
While it is technically possible to bypass this check, an attacker would need to be aware of the script's existence and the specific keyword used in the display names. This makes bypassing the script unlikely in most scenarios.
