Function Get-HawkTenantAdminInboxRuleCreation {
    <#
    .SYNOPSIS
        Retrieves audit log entries for inbox rules that were historically created within the tenant.

    .DESCRIPTION
        This function queries the Microsoft 365 Unified Audit Log for events classified as inbox 
        rule creation (New-InboxRule). It focuses on historical record-keeping and identifying 
        potentially suspicious rules that were created. The logged events do not indicate the 
        specific method or interface used to create the rules.

        Key points:
        - Displays creation events for inbox rules, including who created them and when.
        - Flags created rules that appear suspicious (e.g., rules that forward externally, delete 
          messages, or filter based on suspicious keywords).
        - Does not confirm whether the rules are currently active or still exist.

        For current, active rules, use Get-HawkTenantInboxRules.

    .OUTPUTS
        File: Simple_Admin_Inbox_Rules_Creation.csv/.json  
        Path: \Tenant  
        Description: Simplified view of created inbox rule events.

        File: Admin_Inbox_Rules_Creation.csv/.json  
        Path: \Tenant  
        Description: Detailed audit log data for created inbox rules.

        File: _Investigate_Admin_Inbox_Rules_Creation.csv/.json  
        Path: \Tenant  
        Description: A subset of historically created rules flagged as suspicious.

    .EXAMPLE
        Get-HawkTenantAdminInboxRuleCreation

        Retrieves events for all admin inbox rules created and available within the audit logs within the configured search window.
        
        Remarks: This basic example pulls all inbox rule creations from the audit log and analyzes them for
        suspicious patterns. Output files will be created in the configured Hawk output directory under
        the Tenant subfolder.
    #>
    [CmdletBinding()]
    param()

    Test-EXOConnection
    Send-AIEvent -Event "CmdRun"

    Out-LogFile "Analyzing admin inbox rule creation from audit logs" -Action

    # Create tenant folder if it doesn't exist
    $TenantPath = Join-Path -Path $Hawk.FilePath -ChildPath "Tenant"
    if (-not (Test-Path -Path $TenantPath)) {
        New-Item -Path $TenantPath -ItemType Directory -Force | Out-Null
    }

    try {
        # Search for new inbox rules
        Out-LogFile "Searching audit logs for inbox rule creation events" -Action
        $searchCommand = "Search-UnifiedAuditLog -RecordType ExchangeAdmin -Operations 'New-InboxRule'"
        [array]$NewInboxRules = Get-AllUnifiedAuditLogEntry -UnifiedSearch $searchCommand

        if ($NewInboxRules.Count -gt 0) {
            Out-LogFile ("Found " + $NewInboxRules.Count + " admin inbox rule changes in audit logs") -Information

            # Process and output the results
            $ParsedRules = $NewInboxRules | Get-SimpleUnifiedAuditLog
            if ($ParsedRules) {
                Out-LogFile "Writing parsed admin inbox rule creation data" -Action
                $ParsedRules | Out-MultipleFileType -FilePrefix "Simple_Admin_Inbox_Rules_Creation" -csv -json
                $NewInboxRules | Out-MultipleFileType -FilePrefix "Admin_Inbox_Rules_Creation" -csv -json

                # Check for suspicious rules using the helper function
                $SuspiciousRules = $ParsedRules | Where-Object {
                    $reasons = @()
                    Test-SuspiciousInboxRule -Rule $_ -Reasons ([ref]$reasons)
                }

                if ($SuspiciousRules) {
                    Out-LogFile "Found suspicious admin inbox rule creation requiring investigation" -Notice

                    Out-LogFile "Writing suspicious rule creation data" -Action
                    $SuspiciousRules | Out-MultipleFileType -FilePrefix "_Investigate_Admin_Inbox_Rules_Creation" -csv -json -Notice

                    # Log details about why each rule was flagged
                    foreach ($rule in $SuspiciousRules) {
                        $reasons = @()
                        if (Test-SuspiciousInboxRule -Rule $rule -Reasons ([ref]$reasons)) {
                            Out-LogFile "Found suspicious rule creation: '$($rule.Param_Name)' created by $($rule.UserId) at $($rule.CreationTime)" -Notice
                            Out-LogFile "Reasons for investigation: $($reasons -join '; ')" -Notice
                        }
                    }
                }
            }
            else {
                Out-LogFile "Error: Failed to parse inbox rule audit data" -isError
            }
        }
        else {
            Out-LogFile "No admin inbox rule creation events found in audit logs" -Information
        }
    }
    catch {
        Out-LogFile "Error analyzing admin inbox rule creation: $($_.Exception.Message)" -isError
        Write-Error -ErrorRecord $_ -ErrorAction Continue
    }
}