# Integrity checks for everything UDP downloads: SHA256 hashes and Authenticode signatures.

# SHA256 of a file as lowercase hex, computed with .NET directly. Get-FileHash is not used on
# purpose: in Windows PowerShell 5.1 it is a script function of the Microsoft.PowerShell.Utility
# module rather than a built-in command, and it is missing on some Windows builds (seen on
# Windows 11 build 26300).
function Get-UdpFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Test-UdpFileHash {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    $actual = Get-UdpFileSha256 -Path $Path
    $ok = ($actual -eq $ExpectedSha256.ToLowerInvariant())
    if ($ok) {
        Write-UdpLog "SHA256 OK for $(Split-Path -Leaf $Path) ($actual)" -Level Detail
    }
    else {
        Write-UdpLog "SHA256 MISMATCH for $(Split-Path -Leaf $Path): expected $ExpectedSha256, got $actual" -Level Error
    }
    return $ok
}

# Returns the organisation (O=) part of a certificate subject, handling quoted values
# such as O="Brave Software, Inc.".
function Get-UdpSubjectOrganization {
    param([string]$Subject)
    if ($Subject -match '(?:^|,\s*)O=(?:"([^"]*)"|([^,]*))') {
        if ($Matches[1]) { return $Matches[1].Trim() }
        return $Matches[2].Trim()
    }
    return $null
}

# Checks that a file has a valid Authenticode signature from the expected publisher.
# Returns an object with Valid, Signer and Reason so the caller can log why a file was rejected.
function Test-UdpSignature {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSigner
    )

    $name = Split-Path -Leaf $Path
    $signature = Get-AuthenticodeSignature -LiteralPath $Path

    if ($signature.Status -ne 'Valid') {
        $reason = "signature status is '$($signature.Status)'"
        if ($signature.StatusMessage) { $reason = "$reason ($($signature.StatusMessage))" }
        Write-UdpLog "Signature check FAILED for ${name}: $reason" -Level Error
        return [pscustomobject]@{ Valid = $false; Signer = $null; Reason = $reason }
    }

    $certificate = $signature.SignerCertificate
    $commonName = $certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    $organization = Get-UdpSubjectOrganization -Subject $certificate.Subject

    if ($commonName -eq $ExpectedSigner -or $organization -eq $ExpectedSigner) {
        Write-UdpLog "Signature OK for ${name}: signed by '$commonName'" -Level Detail
        return [pscustomobject]@{ Valid = $true; Signer = $commonName; Reason = $null }
    }

    $reason = "signed by '$commonName', expected '$ExpectedSigner'"
    Write-UdpLog "Signature check FAILED for ${name}: $reason" -Level Error
    return [pscustomobject]@{ Valid = $false; Signer = $commonName; Reason = $reason }
}
