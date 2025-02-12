# Security Policy

## Supported Versions

We actively support the latest major release of **Cops and Robbers**. Please ensure your version is up to date to receive security patches and improvements.

| Version | Supported          |
| ------- | ------------------ |
| 0.0.0     | :white_check_mark: |
| < 0.0.0   | :x:                |

---

## Reporting a Vulnerability

If you discover a security vulnerability in the **Cops and Robbers** game mode, please help us keep the community safe by following these steps:

1. **Report Privately**: Do not create public issues for vulnerabilities. Instead, email us at `security@indom-hub.com` with the details.
   
2. **Include Details**: When reporting, please include as much information as possible:
   - A description of the vulnerability and its impact.
   - Steps to reproduce the issue, if applicable.
   - Any relevant logs, scripts, or screenshots.
   
3. **Response Time**: We will acknowledge receipt of your report within **3 business days**. We strive to provide a resolution within **7-14 days**, depending on the complexity of the issue.

4. **Disclosure Policy**: Once the vulnerability is resolved, we will coordinate with the reporter to determine the best approach for public disclosure. We give credit to reporters for valid findings, if they desire.

---

## Security Improvements in Version 2.0

Version **2.0** includes several important security enhancements:

- **Input Validation**: Improved validation of all player inputs to prevent exploits, injections, and unauthorized access.
- **Admin Command Security**: Ensured that all admin commands have consistent security checks and proper input validation to prevent misuse.
- **Data Handling Optimization**: Enhanced data structures and handling procedures to prevent data leaks and ensure the integrity of player data.
- **Function Definition Corrections**: Resolved issues related to function scopes and definitions to prevent potential script errors and vulnerabilities.
- **Bug Fixes**: Addressed known bugs that could affect game stability and security, such as parameter mismatches and undefined globals.

We strongly recommend updating to **version 2.0** to benefit from these security improvements and to maintain compatibility with the latest features.

---

## Security Recommendations

To help secure your server and player data:

- **Keep Dependencies Updated**: Regularly check for updates to FiveM, GTA V, and this game mode. Staying current helps protect against known vulnerabilities.
- **Enable Two-Factor Authentication (2FA)**: For GitHub accounts, server control panels, and any other accounts that can access the server or repository.
- **Restrict Admin Access**: Limit the number of users with admin permissions within the game mode to reduce the risk of insider threats. Ensure that admin identifiers are securely managed in `admin.lua`.
- **Regular Backups**: Maintain regular backups of your server data to prevent data loss and to enable recovery in case of a security breach.
- **Monitor Server Logs**: Regularly monitor server logs for suspicious activities or unauthorized access attempts.
- **Secure Communication Channels**: Use encrypted connections (e.g., SSL/TLS) for any remote server management tools or databases.

For additional guidance, refer to our [documentation](https://github.com/Indom-hub/Cops-and-Robbers/wiki) and [installation guide](https://github.com/Indom-hub/Cops-and-Robbers).

---

Thank you for helping us maintain the security and integrity of **Cops and Robbers**!
