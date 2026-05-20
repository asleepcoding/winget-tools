function Format-ExceptionDetails {
    <#
    .SYNOPSIS
        Formats an ErrorRecord into a detailed string for logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $ErrorRecord
    )

    $detailParts = New-Object System.Collections.Generic.List[string]
    $detailParts.Add($ErrorRecord.Exception.Message) | Out-Null
    if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.ScriptName) {
        $detailParts.Add(('Script={0}; Line={1}' -f $ErrorRecord.InvocationInfo.ScriptName, $ErrorRecord.InvocationInfo.ScriptLineNumber)) | Out-Null
    }
    if ($ErrorRecord.ScriptStackTrace) {
        $detailParts.Add($ErrorRecord.ScriptStackTrace) | Out-Null
    }
    return ($detailParts -join '; ')
}
