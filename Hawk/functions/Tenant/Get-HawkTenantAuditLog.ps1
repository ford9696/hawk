﻿Function Get-HawkTenantAuditLog{
<#
.SYNOPSIS
Retrieves all Azure AD audit logs for a specified tenant and exports them to a CSV file.

.DESCRIPTION
The Get-HawkTenantAuditLogs function retrieves all Azure AD audit logs for a specified tenant using the Microsoft Graph API. The audit logs are then exported to a CSV file using the Out-MultipleFileType function from the Hawk module.

.EXAMPLE
PS C:\> Get-HawkTenantAuditLogs

This example retrieves all Azure AD audit logs for the "contoso.onmicrosoft.com" tenant and exports them to a CSV file.

.NOTES
This function requires the Microsoft Graph PowerShell module and the Hawk module to be installed. You can install these modules using the following commands:

Install-Module -Name Microsoft.Graph
Install-Module -Name Hawk

.LINK
https://docs.microsoft.com/en-us/graph/api/resources/auditlog?view=graph-rest-1.0

#>
BEGIN{
    #Initializing Hawk Object if not present
    if ([string]::IsNullOrEmpty($Hawk.FilePath)) {
        Initialize-HawkGlobalObject
    }
    Out-LogFile "Gathering Azure AD Audit Logs events" -Action
}
PROCESS{
        $auditLogsResponse = Get-MgAuditLogDirectoryAudit -All
        foreach ($auditLog in $auditLogsResponse) {
            $auditLogs += [PSCustomObject]@{
                Id = $auditLog.Id
                Category = $auditLog.Category
                Result = $auditLog.Result
                ResultReason = $auditLog.ResultReason
                ActivityDisplayName = $auditLog.ActivityDisplayName
                ActivityDateTime = $auditLog.ActivityDateTime
                Target = $auditLog.TargetResources[0].DisplayName
                Type = $auditLog.Target.TargetResources[0].Type
                UserPrincipalName = $auditLog.TargetResources[0].UserPrincipalName
                UserType = $auditLog.UserType
            }
        }
    }
    END{
        $auditLogs | Sort-Object -Property ActivityDateTime | Out-MultipleFileType -FilePrefix "AzureADAuditLog" -csv -json
        Out-Logfile "Completed exporting Azure AD audit logs" -Information
    }
}