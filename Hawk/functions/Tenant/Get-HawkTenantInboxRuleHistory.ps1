Function Get-HawkTenantInboxRuleHistory {
    <#
    .SYNOPSIS
        Retrieves audit log entries for all inbox rules created within the tenant via PowerShell or the ExchangeAdmin Portal, whether they are active or not.

    .DESCRIPTION
        This function queries the Microsoft 365 Unified Audit Logs for events where inbox rules
        were created (New-InboxRule events) via PowerShell or the Exchange Admin Portal. It is focused on historical record-keeping and detection 
        of potentially suspicious rules that were created. 
        
        Key points:
        - Shows  creation events for inbox rules, including who created them and when.
        - Flags any created rules that appear suspicious (e.g., rules that forward 
          externally, delete messages, or target certain keywords).
        - Does not show whether the rules are still active or currently exist in the mailboxes.
        
        For current, active rules, use Get-HawkTenantInboxRules.

    .OUTPUTS
        File: Simple_InboxRules_Creation_History.csv/.json  
        Path: \Tenant  
        Description: Simplified view of created inbox rule events.

        File: InboxRules_Creation_History.csv/.json  
        Path: \Tenant  
        Description: Detailed audit log data for created inbox rules.

        File: _Investigate_InboxRules_Creation_History.csv/.json  
        Path: \Tenant  
        Description: A subset of historically created rules flagged as suspicious.

        File: Investigate_InboxRules_Creation_History_Raw.json  
        Path: \Tenant  
        Description: Raw audit data for suspicious created rules.

    .EXAMPLE
        Get-HawkTenantInboxRuleHistory

        Retrieves events for all created inbox rules from the audit logs within the specified 
        search window, highlighting any that appear suspicious.

    .NOTES
        - Focuses solely on the aspect of rule creation.
        - Does not show if the rules currently exist or are active; it only surfaces past creation events.
        - To view active rules in mailboxes, use Get-HawkTenantInboxRules.
    #>
    [CmdletBinding()]
    param()

    Test-EXOConnection
    Send-AIEvent -Event "CmdRun"

    Out-LogFile "Analyzing inbox rule creation from audit logs" -Action

    # Create tenant folder if it doesn't exist
    $TenantPath = Join-Path -Path $Hawk.FilePath -ChildPath "Tenant"
    if (-not (Test-Path -Path $TenantPath)) {
        New-Item -Path $TenantPath -ItemType Directory -Force | Out-Null
    }

    try {
        # Search for new inbox rules
        Out-LogFile "Searching audit logs for inbox rule changes" -action
        $searchCommand = "Search-UnifiedAuditLog -RecordType ExchangeAdmin -Operations 'New-InboxRule'"
        [array]$NewInboxRules = Get-AllUnifiedAuditLogEntry -UnifiedSearch $searchCommand

        if ($NewInboxRules.Count -gt 0) {
            Out-LogFile ("Found " + $NewInboxRules.Count + " inbox rule changes in audit logs")

            # Write raw audit data for reference
            $RawJsonPath = Join-Path -Path $TenantPath -ChildPath "InboxRules_Creation_History_Raw.json"
            $NewInboxRules | Select-Object -ExpandProperty AuditData | Out-File -FilePath $RawJsonPath

            # Process and output the results
            $ParsedRules = $NewInboxRules | Get-SimpleUnifiedAuditLog
            if ($ParsedRules) {
                # Output simple format for easy analysis
                $ParsedRules | Out-MultipleFileType -FilePrefix "Simple_InboxRules_Creation_History" -csv -json

                # Output full audit logs for complete record
                $NewInboxRules | Out-MultipleFileType -FilePrefix "InboxRules_Creation_History" -csv -json

                # Check for suspicious rules
                $SuspiciousRules = $ParsedRules | Where-Object {
                    $rule = $_

                    # Check for forwarding/redirection
                    ($rule.Param_ForwardTo) -or
                    ($rule.Param_ForwardAsAttachmentTo) -or
                    ($rule.Param_RedirectTo) -or
                    ($rule.Param_DeleteMessage) -or

                    # Check for moves to deleted items
                    ($rule.Param_MoveToFolder -eq 'Deleted Items') -or

                    # Check for suspicious keywords in subject filters
                    ($rule.Param_SubjectContainsWords -match 'password|credentials|login|secure|security') -or

                    # Check for security-related sender filters
                    ($rule.Param_From -match 'security|admin|support|microsoft|helpdesk')
                }

                if ($SuspiciousRules) {
                    Out-LogFile "Found suspicious inbox rule creation requiring investigation" -Notice
                    $SuspiciousRules | Out-MultipleFileType -FilePrefix "_Investigate_InboxRules_Creation_History" -csv -json -Notice

                    # Write raw data for suspicious rules
                    $RawSuspiciousPath = Join-Path -Path $TenantPath -ChildPath "Investigate_InboxRules_Creation_History_Raw.json"
                    $SuspiciousRules | ConvertTo-Json -Depth 10 | Out-File -FilePath $RawSuspiciousPath

                    # Log details about why each rule was flagged
                    foreach ($rule in $SuspiciousRules) {
                        $reasons = @()
                        if ($rule.Param_ForwardTo) { $reasons += "forwards to: $($rule.Param_ForwardTo)" }
                        if ($rule.Param_ForwardAsAttachmentTo) { $reasons += "forwards as attachment to: $($rule.Param_ForwardAsAttachmentTo)" }
                        if ($rule.Param_RedirectTo) { $reasons += "redirects to: $($rule.Param_RedirectTo)" }
                        if ($rule.Param_DeleteMessage) { $reasons += "deletes messages" }
                        if ($rule.Param_MoveToFolder -eq 'Deleted Items') { $reasons += "moves to Deleted Items" }
                        if ($rule.Param_SubjectContainsWords -match 'password|credentials|login|secure|security') {
                            $reasons += "suspicious subject filter: $($rule.Param_SubjectContainsWords)"
                        }
                        if ($rule.Param_From -match 'security|admin|support|microsoft|helpdesk') {
                            $reasons += "targets security sender: $($rule.Param_From)"
                        }

                        Out-LogFile "Found suspicious rule creation: '$($rule.Param_Name)' created by $($rule.UserId) at $($rule.CreationTime)" -Notice
                        Out-LogFile "Reasons for investigation: $($reasons -join '; ')" -Notice
                    }
                }
            }
            else {
                Out-LogFile "Error: Failed to parse inbox rule audit data" -Notice
            }
        }
        else {
            Out-LogFile "No inbox rule changes found in audit logs"
        }
    }
    catch {
        Out-LogFile "Error analyzing inbox rule creation: $($_.Exception.Message)" -Notice
        Write-Error -ErrorRecord $_ -ErrorAction Continue
    }
}