Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PlaceHubMockProvisioning {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateSet('DiscoverResource','CreateDeskPoolWorkspace','CreateParkingResource','ConfigureCalendarProcessing','AssociatePlacesSection','Verify','Reconcile')][string]$Operation,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]{1,64}$')][string]$LogicalResourceId,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$CorrelationId,
        [ValidateSet('standard','restricted')][string]$PolicyTemplate = 'standard'
    )

    # This POC module intentionally contains no Exchange/Graph connection or mutation command.
    if (-not $PSCmdlet.ShouldProcess('OFFLINE_MOCK', $Operation)) {
        return [pscustomobject]@{ State = 'Draft'; Code = 'MOCK_PREVIEW'; CorrelationId = $CorrelationId }
    }
    [pscustomobject]@{ State = 'Succeeded'; Code = 'MOCK_VERIFIED'; CorrelationId = $CorrelationId }
}

Export-ModuleMember -Function Invoke-PlaceHubMockProvisioning
