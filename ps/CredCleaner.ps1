# Credential Cleaner Script
# ---------------------------------
# This script lists credentials using cmdkey and attempts to delete
# credentials where the line contains 'target='.
# WARNING: This script deletes credentials WITHOUT confirmation. Use with caution.

Write-Host "Starting Credential Cleaner..."

# --- Configuration ---
# Regex to find the part of the credential string to delete.
$regexPattern = '(?i)target=(.+)'

# Optional: Define a pattern for filtering. Only credentials matching this pattern will be deleted.
# Leave as $null or empty string ('') to disable filtering. Uses wildcard (*).
# Example: $filterPattern = "*Microsoft*"
$filterPattern = $null
# -------------------


# 1. Get all credentials using cmdkey /list
Write-Host "Retrieving credentials..."
$allCredsOutput = cmdkey /list

# Check if cmdkey /list executed successfully
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Failed to execute 'cmdkey /list'. Exit code: $LASTEXITCODE. Cannot continue."
    # Pause script execution if running in a console that closes immediately
    if ($Host.Name -eq "ConsoleHost") { Read-Host "Press Enter to exit" }
    exit 1 # Exit the script with an error code
}

# Check if any output was received
if ($null -eq $allCredsOutput -or $allCredsOutput.Length -eq 0) {
    Write-Host "No credentials found or 'cmdkey /list' returned no output."
    Write-Host "Credential Cleaner finished."
    if ($Host.Name -eq "ConsoleHost") { Read-Host "Press Enter to exit" }
    exit 0
}

Write-Host "Processing credentials..."
$deletionAttempted = $false

# 2. Iterate through each line of the output
foreach ($line in $allCredsOutput) {
    # 3. Check if the line matches the specified regex pattern
    if ($line -match $regexPattern) {
        # 4. Extract the matched part (the credential name/identifier to delete)
        # $matches[1] holds the content of the first capture group (.+)
        $credNameToDelete = $matches[1].Trim() # Trim() to remove leading/trailing whitespace

        $deletionAttempted = $true # Mark that we found at least one potential match

        # 5. Optional Filtering
        if ($null -ne $filterPattern -and $filterPattern -ne '') {
            if ($credNameToDelete -notlike $filterPattern) {
                # Write-Host "Skipping '$credNameToDelete' (does not match filter '$filterPattern')." # Uncomment for debugging filter
                continue # Skip to the next line if it doesn't match the filter
            }
            # Write-Host "Match found for filter '$filterPattern': '$credNameToDelete'" # Uncomment for debugging filter
        }

        # 6. Attempt to delete the credential
        Write-Host "Attempting to delete target: '$credNameToDelete'..."
        cmdkey /delete:$credNameToDelete

        # 7. Check if deletion was successful
        if ($LASTEXITCODE -eq 0) {
            Write-Host " -> Successfully deleted '$credNameToDelete'." -ForegroundColor Green
        } else {
            Write-Warning " -> Failed to delete '$credNameToDelete'. 'cmdkey /delete' exited with code $LASTEXITCODE."
        }
    }
}

if (-not $deletionAttempted) {
    Write-Host "No lines matched the pattern '$regexPattern'. No deletion attempts were made."
} elseif ($null -ne $filterPattern -and $filterPattern -ne '') {
     Write-Host "Finished processing credentials matching filter '$filterPattern'."
} else {
     Write-Host "Finished processing all credentials matching pattern '$regexPattern'."
}


Write-Host "Credential Cleaner finished."
if ($Host.Name -eq "ConsoleHost") { Read-Host "Press Enter to exit" }