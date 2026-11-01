#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $OutputDirectory,
    [ValidateRange(1, 365)] [int] $ValidityDays = 180
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $envFile = Join-Path (Get-Location) '.env'
    if (Test-Path -LiteralPath $envFile) {
        $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^\s*PLACEHUB_TLS_DIRECTORY\s*=' } | Select-Object -Last 1
        if ($line) { $OutputDirectory = ($line -split '=',2)[1].Trim().Trim('"').Trim("'") }
    }
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PlaceHub/tls' }
}
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path (Get-Location) $OutputDirectory }
$privatePath = Join-Path $OutputDirectory 'client-auth.pfx'
$publicPath = Join-Path $OutputDirectory 'client-auth.cer'
if ((Test-Path -LiteralPath $privatePath) -or (Test-Path -LiteralPath $publicPath)) { throw 'ENTRA_CLIENT_CERTIFICATE_ALREADY_EXISTS' }
if (-not $PSCmdlet.ShouldProcess('configured identity directory','create development Entra client certificate')) { 'ENTRA_CLIENT_CERTIFICATE_PREVIEW_OK'; return }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$rsa = [Security.Cryptography.RSA]::Create(3072)
try {
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=PlaceHub Development Web Authentication',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
    $usage = [Security.Cryptography.OidCollection]::new()
    $null = $usage.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.2'))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($usage,$true))
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddDays($ValidityDays))
    try {
        [IO.File]::WriteAllBytes($privatePath,$certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,''))
        [IO.File]::WriteAllBytes($publicPath,$certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    }
    finally { $certificate.Dispose() }
}
finally { $rsa.Dispose() }
if ($IsWindows) {
    # Private key readable only by the current user; inherited ACEs removed.
    & icacls $privatePath /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ENTRA_CLIENT_CERTIFICATE_PERMISSION_FAILED' }
}
else { & chmod 600 $privatePath; if ($LASTEXITCODE -ne 0) { throw 'ENTRA_CLIENT_CERTIFICATE_PERMISSION_FAILED' } }
'ENTRA_CLIENT_CERTIFICATE_READY'
'ENTRA_PUBLIC_CERTIFICATE_REGISTRATION_REQUIRED'
